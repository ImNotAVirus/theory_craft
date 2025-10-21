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

  The processor maintains a minimal state structure containing:
  - The indicator module reference
  - The indicator's internal state

  All other concerns (data stream names, output names, bar tracking) are managed
  by the indicator itself.

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
  The processor state containing the indicator module and its state.
  """
  @type t :: %__MODULE__{
          indicator_module: module(),
          indicator_state: any()
        }

  defstruct [:indicator_module, :indicator_state]

  ## Processor behaviour

  @doc """
  Initializes the indicator processor with the given options.

  This function extracts the indicator module from the options, then forwards all
  remaining options to the indicator's `init/1` callback to construct the processor state.

  ## Options

    - `:module` (required) - The indicator module implementing `TheoryCraft.Indicator`
    - All other options are passed through to the indicator's `init/1` callback

  The indicator itself is responsible for validating its required options (such as
  `:data` for the data stream name and `:name` for the output name).

  ## Returns

    - `{:ok, state}` - The initial processor state containing the indicator module
      and the indicator's internal state
    - `{:error, reason}` - If the indicator's initialization fails

  ## Examples

      # Initialize with a simple moving average indicator
      iex> IndicatorProcessor.init(module: MyIndicators.SMA, data: "eurusd_m5", name: "sma20", period: 20)
      {:ok, %IndicatorProcessor{
        indicator_module: MyIndicators.SMA,
        indicator_state: %{period: 20, data: "eurusd_m5", name: "sma20"}
      }}

  ## Errors

      # Missing required module option
      iex> IndicatorProcessor.init(data: "eurusd", name: "sma", period: 20)
      ** (ArgumentError) Missing required option: module

  """
  @impl true
  @spec init(Keyword.t()) :: {:ok, t()}
  def init(opts) do
    indicator_module = Utils.required_opt!(opts, :module)

    # Forward all options (except :module) to the indicator
    indicator_opts = Keyword.delete(opts, :module)

    case indicator_module.init(indicator_opts) do
      {:ok, indicator_state} ->
        state = %IndicatorProcessor{
          indicator_module: indicator_module,
          indicator_state: indicator_state
        }

        {:ok, state}

      error ->
        error
    end
  end

  @doc """
  Processes a MarketEvent by delegating to the indicator.

  This function forwards the event to the indicator's `next/2` callback and updates
  the processor state with the indicator's new state. The indicator is responsible for:
  - Extracting the relevant data from the event
  - Determining if it's a new bar
  - Calculating its output value
  - Writing the output to the event

  ## Parameters

    - `event` - The `MarketEvent` to process
    - `state` - The processor state containing the indicator module and its state

  ## Returns

    - `{:ok, updated_event, new_state}` - A tuple containing:
      - `updated_event` - The `MarketEvent` with the indicator output added by the indicator
      - `new_state` - The updated processor state with new indicator state
    - `{:error, reason}` - If the indicator's processing fails

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

      # Process another event
      event2 = %MarketEvent{data: %{"eurusd_m5" => updated_candle}}
      {:ok, updated_event2, newer_state} = IndicatorProcessor.next(event2, new_state)

  """
  @impl true
  @spec next(MarketEvent.t(), t()) :: {:ok, MarketEvent.t(), t()}
  def next(event, %IndicatorProcessor{} = state) do
    %IndicatorProcessor{
      indicator_module: indicator_module,
      indicator_state: indicator_state
    } = state

    case indicator_module.next(event, indicator_state) do
      {:ok, updated_event, new_indicator_state} ->
        new_state = %IndicatorProcessor{state | indicator_state: new_indicator_state}
        {:ok, updated_event, new_state}

      error ->
        error
    end
  end
end
