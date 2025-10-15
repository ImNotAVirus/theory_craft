defmodule TheoryCraft.Processors.IndicatorProcessor do
  @moduledoc """
  A Processor that wraps a `TheoryCraft.Indicator` behaviour for integration into processing pipelines.

  This processor acts as an adapter that allows indicators to participate in GenStage pipelines.
  It handles the initialization and delegation of market events to the wrapped indicator module,
  while maintaining the indicator's internal state and (in the future) historical bar buffer.

  ## Purpose

  Indicators are specialized components for technical analysis that implement the
  `TheoryCraft.Indicator` behaviour. The `IndicatorProcessor` wraps these indicators,
  allowing them to be used seamlessly in `MarketSimulator` pipelines alongside other processors.

  ## Historical Bar Buffer

  Indicators can declare a `loopback/0` value representing how many historical bars they need
  for their calculations. The `IndicatorProcessor` will (in a future version) maintain this
  buffer automatically, providing historical data to the indicator.

  **Note**: Historical bar buffering is not yet implemented. The `bars_history` field is
  currently always `nil` and will be implemented in a future version.

  ## State Management

  The processor maintains its own state structure containing:
  - The indicator module reference
  - The indicator's internal state
  - The historical bars buffer (future feature)

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
  The processor state containing the indicator module, its state, and historical buffer.
  """
  @type t :: %__MODULE__{
          indicator_module: module(),
          indicator_state: any(),
          bars_history: nil
        }

  defstruct [:indicator_module, :indicator_state, :bars_history]

  ## Processor behaviour

  @doc """
  Initializes the indicator processor with the given options.

  This function extracts the indicator module from the options, calls the indicator's
  `init/1` callback with the remaining options, and constructs the processor state.

  ## Options

    - `:module` (required) - The indicator module implementing `TheoryCraft.Indicator`
    - All other options are passed through to the indicator's `init/1` callback

  ## Returns

    - `{:ok, state}` - The initial processor state containing the indicator module,
      indicator state, and bars_history (currently `nil`)

  ## Examples

      # Initialize with a simple moving average indicator
      iex> IndicatorProcessor.init(module: MyIndicators.SMA, period: 20, name: "sma20")
      {:ok, %IndicatorProcessor{
        indicator_module: MyIndicators.SMA,
        indicator_state: %{period: 20, name: "sma20"},
        bars_history: nil
      }}

      # Initialize with RSI indicator
      iex> IndicatorProcessor.init(module: MyIndicators.RSI, period: 14, name: "rsi")
      {:ok, %IndicatorProcessor{
        indicator_module: MyIndicators.RSI,
        indicator_state: %{period: 14, name: "rsi"},
        bars_history: nil
      }}

  ## Errors

      # Missing required module option
      iex> IndicatorProcessor.init(period: 20)
      ** (ArgumentError) Missing required option: module

  """
  @impl true
  @spec init(Keyword.t()) :: {:ok, t()}
  def init(opts) do
    indicator_module = Utils.required_opt!(opts, :module)

    case indicator_module.init(opts) do
      {:ok, indicator_state} ->
        state = %IndicatorProcessor{
          indicator_module: indicator_module,
          indicator_state: indicator_state,
          bars_history: nil
        }

        {:ok, state}

      error ->
        error
    end
  end

  @doc """
  Processes a MarketEvent by delegating to the wrapped indicator module.

  This function delegates the event processing to the indicator's `next/2` callback,
  maintaining the indicator's internal state across calls. The historical bar buffer
  (when implemented) will also be updated here.

  ## Parameters

    - `event` - The `MarketEvent` to process
    - `state` - The processor state containing the indicator module and its state

  ## Returns

    - `{:ok, updated_event, new_state}` - A tuple containing:
      - `updated_event` - The `MarketEvent` transformed by the indicator
      - `new_state` - The updated processor state with new indicator state

  ## Examples

      # Process a market event through an SMA indicator
      {:ok, state} = IndicatorProcessor.init(module: MyIndicators.SMA, period: 5, name: "sma5")

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

      # Process another event with updated state
      event2 = %MarketEvent{data: %{"eurusd_m5" => next_candle}}
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
