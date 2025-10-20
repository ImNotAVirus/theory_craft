defmodule TheoryCraft.Processors.IndicatorProcessor do
  @moduledoc """
  A Processor that wraps a `TheoryCraft.Indicator` behaviour for integration into processing pipelines.

  This processor acts as an adapter that allows indicators to participate in GenStage pipelines.
  It handles the initialization and delegation of values from market events to the wrapped indicator module,
  while maintaining the indicator's internal state and tracking bar boundaries.

  ## Purpose

  Indicators are specialized components for technical analysis that implement the
  `TheoryCraft.Indicator` behaviour. The `IndicatorProcessor` wraps these indicators,
  allowing them to be used seamlessly in `MarketSimulator` pipelines alongside other processors.

  ## State Management

  The processor maintains its own state structure containing:
  - The indicator module reference
  - The indicator's internal state
  - The data stream name to read from
  - The output name to write the indicator value to
  - The last bar timestamp for detecting new bars

  ## Examples

      # Creating an indicator processor for a custom SMA indicator
      alias TheoryCraft.Processors.IndicatorProcessor

      {:ok, processor_state} = IndicatorProcessor.init(
        module: MyIndicators.SMA,
        period: 20,
        name: "sma20"
      )

      # Process an event through the indicator
      event = %MarketEvent{data: %{"eurusd_m5" => candle}}
      {:ok, updated_event, new_state} = IndicatorProcessor.next(event, processor_state)

      # The updated event now contains the indicator output
      updated_event.data["sma20"]  # => SMA value

  ## Integration with MarketSimulator

  Indicators are typically added to a simulator using helper methods that automatically
  wrap them in an `IndicatorProcessor`:

      simulator = %MarketSimulator{}
      |> MarketSimulator.add_data(candle_stream, name: "eurusd_m5")
      |> MarketSimulator.add_indicator(MyIndicators.SMA, period: 20, name: "sma20")
      |> MarketSimulator.stream()

  See `TheoryCraft.MarketSimulator` for more details.

  """

  alias __MODULE__
  alias TheoryCraft.MarketEvent
  alias TheoryCraft.Utils

  @behaviour TheoryCraft.Processor

  @typedoc """
  The processor state containing the indicator module, its state, data stream configuration, and last bar tracking.
  """
  @type t :: %__MODULE__{
          indicator_module: module(),
          indicator_state: any(),
          data_name: String.t(),
          output_name: String.t(),
          last_bar_time: DateTime.t() | nil
        }

  defstruct [:indicator_module, :indicator_state, :data_name, :output_name, :last_bar_time]

  ## Processor behaviour

  @doc """
  Initializes the indicator processor with the given options.

  This function extracts the indicator module, data stream name, and output name from the options,
  calls the indicator's `init/1` callback with the remaining options, and constructs the processor state.

  ## Options

    - `:module` (required) - The indicator module implementing `TheoryCraft.Indicator`
    - `:data` (required) - The name of the data stream to read values from
    - `:name` (required) - The name to use for the indicator output in the event data
    - All other options are passed through to the indicator's `init/1` callback

  ## Returns

    - `{:ok, state}` - The initial processor state containing the indicator module,
      indicator state, data/output names, and last_bar_time (initially `nil`)

  ## Examples

      # Initialize with a simple moving average indicator
      iex> IndicatorProcessor.init(module: MyIndicators.SMA, data: "eurusd_m5", name: "sma20", period: 20)
      {:ok, %IndicatorProcessor{
        indicator_module: MyIndicators.SMA,
        indicator_state: %{period: 20},
        data_name: "eurusd_m5",
        output_name: "sma20",
        last_bar_time: nil
      }}

  ## Errors

      # Missing required module option
      iex> IndicatorProcessor.init(data: "eurusd", name: "sma", period: 20)
      ** (ArgumentError) Missing required option: module

      # Missing required data option
      iex> IndicatorProcessor.init(module: MyIndicators.SMA, name: "sma", period: 20)
      ** (ArgumentError) Missing required option: data

      # Missing required name option
      iex> IndicatorProcessor.init(module: MyIndicators.SMA, data: "eurusd", period: 20)
      ** (ArgumentError) Missing required option: name

  """
  @impl true
  @spec init(Keyword.t()) :: {:ok, t()}
  def init(opts) do
    indicator_module = Utils.required_opt!(opts, :module)
    data_name = Utils.required_opt!(opts, :data)
    output_name = Utils.required_opt!(opts, :name)

    case indicator_module.init(opts) do
      {:ok, indicator_state} ->
        state = %IndicatorProcessor{
          indicator_module: indicator_module,
          indicator_state: indicator_state,
          data_name: data_name,
          output_name: output_name,
          last_bar_time: nil
        }

        {:ok, state}

      error ->
        error
    end
  end

  @doc """
  Processes a MarketEvent by extracting the value, delegating to the indicator, and writing the result.

  This function:
  1. Extracts the value from the event's data map using the configured data stream name
  2. Determines if it's a new bar by comparing timestamps with the last processed bar
  3. Delegates to the indicator's `next/3` callback with the value and new bar flag
  4. Writes the indicator's output to the event's data map with the configured output name
  5. Updates the last bar timestamp

  ## Parameters

    - `event` - The `MarketEvent` to process
    - `state` - The processor state containing the indicator module and its state

  ## Returns

    - `{:ok, updated_event, new_state}` - A tuple containing:
      - `updated_event` - The `MarketEvent` with the indicator output added
      - `new_state` - The updated processor state with new indicator state and last bar time

  ## Examples

      # Process a market event through an SMA indicator
      {:ok, state} = IndicatorProcessor.init(
        module: MyIndicators.SMA,
        data: "eurusd_m5",
        name: "sma5",
        period: 5
      )

      candle = %TheoryCraft.Candle{
        time: ~U[2024-01-01 10:00:00Z],
        open: 100.0,
        high: 102.0,
        low: 99.0,
        close: 101.0,
        volume: 1000.0
      }

      event = %MarketEvent{data: %{"eurusd_m5" => candle}}
      {:ok, updated_event, new_state} = IndicatorProcessor.next(event, state)

      # The indicator has added its output to the event
      updated_event.data["sma5"]  # => SMA value calculated by the indicator

      # Process another event with the same timestamp (update to current bar)
      event2 = %MarketEvent{data: %{"eurusd_m5" => updated_candle}}
      {:ok, updated_event2, newer_state} = IndicatorProcessor.next(event2, new_state)

  """
  @impl true
  @spec next(MarketEvent.t(), t()) :: {:ok, MarketEvent.t(), t()}
  def next(event, %IndicatorProcessor{} = state) do
    %IndicatorProcessor{
      indicator_module: indicator_module,
      indicator_state: indicator_state,
      data_name: data_name
    } = state

    case Map.fetch(event.data, data_name) do
      {:ok, _value} ->
        # Call the indicator with the full MarketEvent
        case indicator_module.next(event, indicator_state) do
          {:ok, updated_event, new_indicator_state} ->
            # Update the processor state
            new_state = %IndicatorProcessor{
              state
              | indicator_state: new_indicator_state
            }

            {:ok, updated_event, new_state}

          error ->
            error
        end

      :error ->
        # Data stream not found, pass through unchanged
        {:ok, event, state}
    end
  end
end
