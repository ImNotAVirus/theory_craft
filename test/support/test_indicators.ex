defmodule TheoryCraft.TestIndicators do
  @moduledoc false
  # Test indicator modules for testing IndicatorProcessor behavior

  alias TheoryCraft.MarketEvent

  defmodule SimpleIndicator do
    @moduledoc false
    # A simple test indicator that returns a constant value

    @behaviour TheoryCraft.Indicator

    alias TheoryCraft.MarketEvent

    @impl true
    def init(opts) do
      constant = Keyword.get(opts, :constant, 10.0)
      data_name = Keyword.fetch!(opts, :data)
      output_name = Keyword.fetch!(opts, :name)

      {:ok, %{constant: constant, data_name: data_name, output_name: output_name}}
    end

    @impl true
    def next(event, state) do
      %{constant: constant, output_name: output_name} = state

      # Simply write the constant value to the event
      updated_data = Map.put(event.data, output_name, constant)
      updated_event = %MarketEvent{event | data: updated_data}

      {:ok, updated_event, state}
    end
  end

  defmodule SMAIndicator do
    @moduledoc false
    # A test SMA indicator that maintains a simple moving average

    @behaviour TheoryCraft.Indicator

    alias TheoryCraft.MarketEvent

    @impl true
    def init(opts) do
      period = Keyword.get(opts, :period, 5)
      data_name = Keyword.fetch!(opts, :data)
      output_name = Keyword.fetch!(opts, :name)

      {:ok, %{period: period, values: [], data_name: data_name, output_name: output_name}}
    end

    @impl true
    def next(event, state) do
      %{period: period, values: values, data_name: data_name, output_name: output_name} = state

      # Extract value from event
      value = event.data[data_name]

      # Extract close price from candle
      close =
        case value do
          %TheoryCraft.Candle{close: close} -> close
          %{close: close} -> close
          v when is_number(v) -> v
          _ -> 0.0
        end

      # Add value to history
      new_values = [close | values] |> Enum.take(period)

      # Calculate SMA
      sma =
        if length(new_values) > 0 do
          Enum.sum(new_values) / length(new_values)
        else
          nil
        end

      new_state = %{state | values: new_values}

      # Write SMA value to event
      updated_data = Map.put(event.data, output_name, sma)
      updated_event = %MarketEvent{event | data: updated_data}

      {:ok, updated_event, new_state}
    end
  end

  defmodule FailingIndicator do
    @moduledoc false
    # An indicator that fails during init for error testing

    @behaviour TheoryCraft.Indicator

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
