defmodule TheoryCraft.TestIndicators do
  @moduledoc false
  # Test indicator modules for testing IndicatorProcessor behavior

  defmodule SimpleIndicator do
    @moduledoc false
    # A simple test indicator that counts events and adds a constant value

    @behaviour TheoryCraft.Indicator

    @impl true
    def loopback(), do: 0

    @impl true
    def init(opts) do
      output_name = Keyword.get(opts, :name, "simple")
      constant = Keyword.get(opts, :constant, 10.0)

      {:ok, %{output_name: output_name, constant: constant, event_count: 0}}
    end

    @impl true
    def next(event, state) do
      %{output_name: output_name, constant: constant, event_count: count} = state

      # Add constant to all candle close prices
      updated_data =
        event.data
        |> Enum.map(fn
          {key, %TheoryCraft.Candle{close: close} = candle} ->
            {key, %TheoryCraft.Candle{candle | close: close + constant}}

          other ->
            other
        end)
        |> Map.new()

      # Also add indicator output
      updated_data = Map.put(updated_data, output_name, constant)

      updated_event = %TheoryCraft.MarketEvent{event | data: updated_data}
      new_state = %{state | event_count: count + 1}

      {:ok, updated_event, new_state}
    end
  end

  defmodule SMAIndicator do
    @moduledoc false
    # A test SMA indicator that maintains a simple moving average

    @behaviour TheoryCraft.Indicator

    @impl true
    def loopback(), do: 20

    @impl true
    def init(opts) do
      period = Keyword.get(opts, :period, 5)
      input_name = Keyword.get(opts, :input, "candle")
      output_name = Keyword.get(opts, :name, "sma")

      {:ok,
       %{
         period: period,
         input_name: input_name,
         output_name: output_name,
         values: []
       }}
    end

    @impl true
    def next(event, state) do
      %{period: period, input_name: input_name, output_name: output_name, values: values} =
        state

      case Map.fetch(event.data, input_name) do
        {:ok, %TheoryCraft.Candle{close: close}} ->
          # Add current close to values and keep only last 'period' values
          new_values = [close | values] |> Enum.take(period)
          sma = Enum.sum(new_values) / length(new_values)

          updated_data = Map.put(event.data, output_name, sma)
          updated_event = %TheoryCraft.MarketEvent{event | data: updated_data}
          new_state = %{state | values: new_values}

          {:ok, updated_event, new_state}

        :error ->
          {:ok, event, state}
      end
    end
  end

  defmodule FailingIndicator do
    @moduledoc false
    # An indicator that fails during init for error testing

    @behaviour TheoryCraft.Indicator

    @impl true
    def loopback(), do: 0

    @impl true
    def init(_opts) do
      case :erlang.phash2(1, 1) do
        0 -> {:error, :init_failed}
        # The second case is never reached, but prevents Dialyzer warnings
        _ -> {:ok, %{}}
      end
    end

    @impl true
    def next(_event, _state) do
      raise "Should not be called"
    end
  end
end
