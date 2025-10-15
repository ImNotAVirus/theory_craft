defmodule TheoryCraft.Indicator do
  @moduledoc """
  Behaviour for stateful indicators that transform market data with historical lookback support.

  An Indicator is a specialized component that processes market data (typically candles)
  to calculate technical indicators like moving averages, RSI, MACD, etc. Indicators are
  similar to Processors but include support for maintaining a historical buffer of candles
  for lookback calculations.

  ## Indicators vs Processors

  While both Indicators and Processors transform `MarketEvent` structs, they serve different purposes:

  - **Processors** (`TheoryCraft.Processor`): General-purpose data transformation components.
    Examples: converting ticks to candles, filtering events, data enrichment.

  - **Indicators** (`TheoryCraft.Indicator`): Specialized for technical analysis calculations
    that require historical data. Examples: SMA, EMA, RSI, MACD, Bollinger Bands.

  Indicators are wrapped by `TheoryCraft.Processors.IndicatorProcessor` to integrate into
  the processing pipeline.

  ## Indicator Lifecycle

  1. **Loopback declaration** (`loopback/0`): Declares how many historical bars to keep
  2. **Initialization** (`init/1`): Called once at the start to set up initial state
  3. **Processing** (`next/2`): Called for each event, receives the event and current state,
     returns the transformed event and new state

  ## Implementing an Indicator

  To create a custom indicator, implement the `TheoryCraft.Indicator` behaviour:

      defmodule MyIndicator.SMA do
        @behaviour TheoryCraft.Indicator

        @impl true
        def loopback(), do: 20  # Keep 20 bars for 20-period SMA

        @impl true
        def init(opts) do
          period = Keyword.get(opts, :period, 20)
          output_name = Keyword.get(opts, :name, "sma")
          state = %{period: period, output_name: output_name}
          {:ok, state}
        end

        @impl true
        def next(event, state) do
          # Calculate SMA using historical bars (when available)
          # For now, historical bars are not yet implemented
          sma_value = calculate_sma(event, state)

          updated_data = Map.put(event.data, state.output_name, sma_value)
          updated_event = %TheoryCraft.MarketEvent{event | data: updated_data}

          {:ok, updated_event, state}
        end

        defp calculate_sma(event, state) do
          # Implementation here
        end
      end

  ## Built-in Indicators

  Currently, there are no built-in indicators. Users can create custom indicators
  by implementing this behaviour.

  ## Integration with MarketSimulator

  Indicators are used through `TheoryCraft.Processors.IndicatorProcessor`:

      simulator = %MarketSimulator{}
      |> MarketSimulator.add_data(candle_stream, name: "eurusd_m5")
      |> MarketSimulator.add_indicator(MyIndicator.SMA, period: 20, name: "sma20")
      |> MarketSimulator.stream()

  See `TheoryCraft.MarketSimulator` for more details on building processing pipelines.
  """

  alias TheoryCraft.MarketEvent

  @typedoc """
  An Indicator specification as a tuple of module and options, or just a module.

  When only the module is provided, options is an empty list.
  """
  @type spec :: {module(), Keyword.t()} | module()

  @doc """
  Returns the number of historical bars (candles) to keep in the indicator's buffer.

  This callback is called once during indicator initialization to determine how many
  historical bars should be maintained for lookback calculations. The value returned
  affects memory usage and the minimum number of bars needed before the indicator
  can produce valid output.

  **Note**: Historical bar buffer is not yet implemented in the current version.
  This callback is declared for future use.

  ## Returns

    - A non-negative integer representing the number of bars to keep in history

  ## Examples

      # Simple Moving Average with 20-period lookback
      def loopback(), do: 20

      # RSI with 14-period lookback
      def loopback(), do: 14

      # Indicator that doesn't need historical data
      def loopback(), do: 0

      # Bollinger Bands with 20-period SMA
      def loopback(), do: 20

  ## Guidelines

  - Return `0` if your indicator doesn't need historical data
  - For moving averages, return the period length
  - For indicators with multiple periods (e.g., MACD), return the largest period
  - Consider memory usage: larger values consume more memory
  """
  @callback loopback() :: non_neg_integer()

  @doc """
  Initializes the indicator with the given options.

  This callback is invoked once when the indicator is added to a pipeline. It should
  return `{:ok, state}` where `state` is the initial state that will be passed to
  subsequent `next/2` calls.

  ## Parameters

    - `opts` - Keyword list of options for configuring the indicator. The available
      options depend on the specific indicator implementation. Common options include:
      - `:period` - Calculation period (e.g., 20 for SMA-20)
      - `:name` - Output name for the indicator value in the event data
      - `:data` - Name of the input data stream to read from

  ## Returns

    - `{:ok, state}` - The initial indicator state

  ## Examples

      # Simple indicator with default period
      def init(opts) do
        period = Keyword.get(opts, :period, 14)
        {:ok, %{period: period}}
      end

      # Indicator with required parameters
      def init(opts) do
        period = Keyword.fetch!(opts, :period)
        output_name = Keyword.get(opts, :name, "indicator")

        state = %{
          period: period,
          output_name: output_name,
          values: []
        }

        {:ok, state}
      end

      # Indicator that validates configuration
      def init(opts) do
        period = Keyword.get(opts, :period, 14)

        if period < 1 do
          raise ArgumentError, "Period must be positive, got: \#{period}"
        end

        {:ok, %{period: period}}
      end

  """
  @callback init(opts :: Keyword.t()) :: {:ok, state :: any()}

  @doc """
  Processes a single market event and returns the transformed event with updated state.

  This callback is invoked for each event in the stream. It receives the current event
  and the indicator's state, and must return the transformed event along with the new state.

  The indicator typically:
  - Reads candle data from the event's data map
  - Calculates the indicator value (using current and historical data)
  - Writes the indicator value to a new key in the event's data map
  - Updates internal state for the next calculation

  **Note**: Historical bar buffer is not yet available. Indicators currently only have
  access to the current event. Full historical lookback support will be added in a future version.

  ## Parameters

    - `event` - The current `MarketEvent` to process
    - `state` - The current indicator state (from `init/1` or previous `next/2` call)

  ## Returns

    - `{:ok, updated_event, new_state}` - A tuple containing:
      - `updated_event` - The transformed `MarketEvent`
      - `new_state` - The updated indicator state for the next event

  ## Examples

      # Simple indicator that adds a constant value
      def next(event, state) do
        candle = event.data["eurusd_m5"]
        indicator_value = candle.close + state.offset

        updated_data = Map.put(event.data, "my_indicator", indicator_value)
        updated_event = %MarketEvent{event | data: updated_data}

        {:ok, updated_event, state}
      end

      # Indicator that maintains state
      def next(event, state) do
        candle = event.data[state.input_name]

        # Add current value to history
        values = [candle.close | state.values] |> Enum.take(state.period)

        # Calculate indicator
        indicator_value = Enum.sum(values) / length(values)

        # Update event
        updated_data = Map.put(event.data, state.output_name, indicator_value)
        updated_event = %MarketEvent{event | data: updated_data}

        # Update state
        new_state = %{state | values: values}

        {:ok, updated_event, new_state}
      end

      # Indicator that reads from specific data stream
      def next(event, state) do
        %{input_name: input_name, output_name: output_name} = state

        case Map.fetch(event.data, input_name) do
          {:ok, candle} ->
            indicator_value = calculate(candle, state)
            updated_data = Map.put(event.data, output_name, indicator_value)
            updated_event = %MarketEvent{event | data: updated_data}
            {:ok, updated_event, state}

          :error ->
            # Input data not found, pass through unchanged
            {:ok, event, state}
        end
      end

  """
  @callback next(event :: MarketEvent.t(), state :: any()) ::
              {:ok, updated_event :: MarketEvent.t(), new_state :: any()}
end
