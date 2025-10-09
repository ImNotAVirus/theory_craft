defmodule TheoryCraft.Processors.TickToCandleProcessor do
  @moduledoc """
  Transforms tick data into candle data.
  """

  alias __MODULE__
  alias TheoryCraft.{Candle, Tick}
  alias TheoryCraft.MarketEvent
  alias TheoryCraft.TimeFrame
  alias TheoryCraft.Utils

  @behaviour TheoryCraft.Processor

  defstruct name: nil,
            data_name: nil,
            market_open: nil,
            timeframe: nil,
            current_candle: nil,
            # Used to track the next candle's opening time (only for candles)
            next_time: nil,
            # Used to count the number of ticks received (only for tick timeframe)
            tick_counter: nil,
            # Used to track the price type for Tick data (mid, bid, ask)
            price_type: nil,
            # If volume is missing in Tick data, use fake volume of 1 per tick
            fake_volume?: true

  ## Processor behaviour

  @impl true
  def init(opts) do
    data_name = Utils.required_opt!(opts, :data)
    timeframe_from_user = Utils.required_opt!(opts, :timeframe)
    name = Keyword.get(opts, :name, "#{data_name}_#{timeframe_from_user}")
    price_type = Keyword.get(opts, :price_type, :mid)
    fake_volume? = Keyword.get(opts, :fake_volume?, true)

    market_open = opts |> Keyword.get(:market_open, ~T[00:00:00]) |> Time.truncate(:second)
    timeframe = TimeFrame.parse!(timeframe_from_user)

    state = %TickToCandleProcessor{
      name: name,
      data_name: data_name,
      market_open: market_open,
      timeframe: timeframe,
      price_type: price_type,
      fake_volume?: fake_volume?
    }

    {:ok, state}
  end

  @impl true
  def next(event, %TickToCandleProcessor{timeframe: {"t", _mult}, tick_counter: nil} = state) do
    %TickToCandleProcessor{
      data_name: data_name,
      price_type: price_type,
      fake_volume?: fake_volume?
    } = state

    tick = market_data_tick!(event, data_name)
    candle = candle_from_tick(tick, price_type, fake_volume?)

    updated_event = %MarketEvent{event | data: Map.put(event.data, data_name, candle)}
    updated_state = %TickToCandleProcessor{state | tick_counter: 1, current_candle: candle}

    {:ok, updated_event, updated_state}
  end

  @impl true
  def next(event, %TickToCandleProcessor{timeframe: {"t", _mult}} = state) do
    %TickToCandleProcessor{
      data_name: data_name,
      price_type: price_type,
      current_candle: current_candle,
      fake_volume?: fake_volume?,
      tick_counter: tick_counter
    } = state

    tick = market_data_tick!(event, data_name)
    new_candle? = new_candle?(tick, state)

    candle =
      case new_candle? do
        true -> candle_from_tick(tick, price_type, fake_volume?)
        false -> update_candle_from_tick(current_candle, tick, price_type, fake_volume?)
      end

    updated_event = %MarketEvent{event | data: Map.put(event.data, data_name, candle)}

    updated_state = %TickToCandleProcessor{
      state
      | tick_counter: if(new_candle?, do: 1, else: tick_counter + 1),
        current_candle: candle
    }

    {:ok, updated_event, updated_state}
  end

  # @impl true
  # def next(event, state) do
  #   {:ok, event, state}
  # end

  ## Private functions

  defp tick_price(%Tick{ask: ask}, :ask), do: ask
  defp tick_price(%Tick{bid: bid}, :bid), do: bid

  defp tick_price(%Tick{ask: ask, bid: bid}, :mid) do
    case {ask, bid} do
      {nil, nil} -> raise "Both ask and bid can't be nil"
      {ask, nil} -> ask
      {nil, bid} -> bid
      {ask, bid} -> (ask + bid) / 2
    end
  end

  defp volume(%Tick{ask_volume: ask_volume, bid_volume: bid_volume}, fake_volume?) do
    case {ask_volume, bid_volume} do
      {nil, nil} -> if fake_volume?, do: 1.0, else: nil
      {ask_volume, nil} -> ask_volume
      {nil, bid_volume} -> bid_volume
      {ask_volume, bid_volume} -> ask_volume + bid_volume
    end
  end

  defp market_data_tick!(event, name) do
    case event do
      %MarketEvent{data: %{^name => %Tick{} = tick}} -> tick
      %MarketEvent{data: %{^name => value}} -> raise "Data must be Tick, got #{inspect(value)}"
    end
  end

  defp new_candle?(%Tick{} = tick, %TickToCandleProcessor{timeframe: {"t", mult}} = state) do
    %Tick{time: time} = tick

    %TickToCandleProcessor{
      tick_counter: counter,
      market_open: market_open,
      current_candle: %Candle{time: candle_dt}
    } = state

    candle_time = DateTime.to_time(candle_dt)
    tick_time = DateTime.to_time(time)

    cond do
      counter >= mult ->
        true

      Time.compare(candle_time, market_open) == :lt and
          Time.compare(tick_time, market_open) != :lt ->
        true

      true ->
        false
    end
  end

  defp candle_from_tick(%Tick{time: time} = tick, price_type, fake_volume?) do
    price = tick_price(tick, price_type)
    volume = volume(tick, fake_volume?)

    %Candle{
      time: time,
      open: price,
      high: price,
      low: price,
      close: price,
      volume: volume
    }
  end

  defp update_candle_from_tick(candle, tick, price_type, fake_volume?) do
    %Candle{volume: prev_volume, high: high, low: low} = candle

    price = tick_price(tick, price_type)
    volume = volume(tick, fake_volume?)

    final_volume =
      case {prev_volume, volume} do
        {nil, nil} -> nil
        {nil, volume} -> volume
        {prev_volume, nil} -> prev_volume
        {prev_volume, volume} -> prev_volume + volume
      end

    %Candle{
      candle
      | high: max(high, price),
        low: min(low, price),
        close: price,
        volume: final_volume
    }
  end
end
