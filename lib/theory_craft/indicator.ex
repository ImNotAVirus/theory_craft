defmodule TheoryCraft.Indicator do
  @moduledoc """
  Behaviour for stateful indicators that process values to calculate technical indicators.

  An Indicator is a specialized component that processes values (typically bar data)
  to calculate technical indicators like moving averages, RSI, MACD, etc. Indicators are
  wrapped by `TheoryCraft.Processors.IndicatorProcessor` to integrate into the processing
  pipeline.

  ## Indicators vs Processors

  While both Indicators and Processors transform data, they serve different purposes:

  - **Processors** (`TheoryCraft.Processor`): General-purpose data transformation components
    that work with `MarketEvent` structs. Examples: converting ticks to bars, filtering
    events, data enrichment.

  - **Indicators** (`TheoryCraft.Indicator`): Specialized for technical analysis calculations
    that work with individual values. Examples: SMA, EMA, RSI, MACD, Bollinger Bands.
    They are wrapped by `IndicatorProcessor` to integrate into the event pipeline.

  ## Indicator Lifecycle

  1. **Initialization** (`init/1`): Called once at the start to set up initial state
  2. **Processing** (`next/3`): Called for each value, receives the value, a flag indicating
     if it's a new bar, and the current state, returns the calculated indicator value and new state

  ## Implementing an Indicator

  To create a custom indicator, implement the `TheoryCraft.Indicator` behaviour:

      defmodule MyIndicator.SMA do
        @behaviour TheoryCraft.Indicator

        @impl true
        def init(opts) do
          period = Keyword.get(opts, :period, 20)
          state = %{period: period, values: []}
          {:ok, state}
        end

        @impl true
        def next(bar, is_new_bar, state) do
          %{period: period, values: values} = state

          # On a new bar, add the value to history
          new_values =
            if is_new_bar do
              [bar.close | values] |> Enum.take(period)
            else
              # Update the last value if it's the same bar
              case values do
                [_last | rest] -> [bar.close | rest]
                [] -> [bar.close]
              end
            end

          # Calculate SMA
          sma_value =
            if length(new_values) > 0 do
              Enum.sum(new_values) / length(new_values)
            else
              nil
            end

          new_state = %{state | values: new_values}

          {:ok, sma_value, new_state}
        end
      end

  ## Built-in Indicators

  Currently, there are no built-in indicators. Users can create custom indicators
  by implementing this behaviour.

  ## Integration with MarketSimulator

  Indicators are used through `TheoryCraft.Processors.IndicatorProcessor`:

      simulator = %MarketSimulator{}
      |> MarketSimulator.add_data(bar_stream, name: "eurusd_m5")
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
  Initializes the indicator with the given options.

  This callback is invoked once when the indicator is added to a pipeline. It should
  return `{:ok, state}` where `state` is the initial state that will be passed to
  subsequent `next/3` calls.

  ## Parameters

    - `opts` - Keyword list of options for configuring the indicator. The available
      options depend on the specific indicator implementation. Common options include:
      - `:period` - Calculation period (e.g., 20 for SMA-20)

  ## Returns

    - `{:ok, state}` - The initial indicator state

  ## Examples

      # Simple indicator with default period
      def init(opts) do
        period = Keyword.get(opts, :period, 14)
        {:ok, %{period: period, values: []}}
      end

      # Indicator with required parameters
      def init(opts) do
        period = Keyword.fetch!(opts, :period)

        state = %{
          period: period,
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

        {:ok, %{period: period, values: []}}
      end

  """
  @callback init(opts :: Keyword.t()) :: {:ok, state :: any()}

  @doc """
  Processes a market event and returns the updated event with indicator value.

  This callback is invoked for each market event in the stream. It receives the current event
  and the indicator's state, and must return the updated event with the indicator value added
  along with the new state.

  ## Parameters

    - `event` - The `MarketEvent` to process
    - `state` - The current indicator state (from `init/1` or previous `next/2` call)

  ## Returns

    - `{:ok, updated_event, new_state}` - A tuple containing:
      - `updated_event` - The `MarketEvent` with the indicator value added
      - `new_state` - The updated indicator state for the next event

  ## Examples

      # Simple indicator that returns the close price
      def next(event, state) do
        %{data_name: data_name, output_name: output_name} = state
        bar = event.data[data_name]

        updated_data = Map.put(event.data, output_name, bar.close)
        updated_event = %MarketEvent{event | data: updated_data}

        {:ok, updated_event, state}
      end

      # Moving average that maintains history
      def next(event, state) do
        %{period: period, values: values, data_name: data_name, output_name: output_name} = state
        bar = event.data[data_name]

        # Add value to history
        new_values = [bar.close | values] |> Enum.take(period)

        # Calculate average
        ma_value =
          if length(new_values) > 0 do
            Enum.sum(new_values) / length(new_values)
          else
            nil
          end

        new_state = %{state | values: new_values}

        updated_data = Map.put(event.data, output_name, ma_value)
        updated_event = %MarketEvent{event | data: updated_data}

        {:ok, updated_event, new_state}
      end

  """
  @callback next(event :: MarketEvent.t(), state :: any()) ::
              {:ok, updated_event :: MarketEvent.t(), new_state :: any()}
end
