defmodule TheoryCraft.Processors.TickToCandleProcessorTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.{Candle, MarketEvent, Tick}
  alias TheoryCraft.Processors.TickToCandleProcessor

  ## Tests

  describe "init/1" do
    test "initializes with required options" do
      opts = [data: "xauusd", timeframe: "t5"]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert %TickToCandleProcessor{} = state
      assert state.data_name == "xauusd"
      assert state.timeframe == {"t", 5}
      assert state.name == "xauusd_t5"
      assert state.price_type == :mid
      assert state.fake_volume? == true
      assert state.market_open == ~T[00:00:00]
      assert state.current_candle == nil
      assert state.tick_counter == nil
    end

    test "initializes with custom name" do
      opts = [data: "xauusd", timeframe: "t5", name: "custom_name"]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.name == "custom_name"
    end

    test "initializes with custom price_type :bid" do
      opts = [data: "xauusd", timeframe: "t5", price_type: :bid]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.price_type == :bid
    end

    test "initializes with custom price_type :ask" do
      opts = [data: "xauusd", timeframe: "t5", price_type: :ask]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.price_type == :ask
    end

    test "initializes with fake_volume? false" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: false]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.fake_volume? == false
    end

    test "initializes with custom market_open" do
      opts = [data: "xauusd", timeframe: "t5", market_open: ~T[09:30:00]]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.market_open == ~T[09:30:00]
    end

    test "raises error when data option is missing" do
      opts = [timeframe: "t5"]

      assert_raise ArgumentError, ~r/Missing required option: data/, fn ->
        TickToCandleProcessor.init(opts)
      end
    end

    test "raises error when timeframe option is missing" do
      opts = [data: "xauusd"]

      assert_raise ArgumentError, ~r/Missing required option: timeframe/, fn ->
        TickToCandleProcessor.init(opts)
      end
    end
  end

  describe "next/2 - first tick (initialization)" do
    test "creates first candle from tick with :mid price" do
      opts = [data: "xauusd", timeframe: "t5"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert %Candle{} = candle
      assert candle.time == ~U[2024-01-01 10:00:00Z]
      assert candle.open == 2001.0
      assert candle.high == 2001.0
      assert candle.low == 2001.0
      assert candle.close == 2001.0
      assert candle.volume == 1.0

      assert new_state.tick_counter == 1
      assert new_state.current_candle == candle
    end

    test "creates first candle with :bid price" do
      opts = [data: "xauusd", timeframe: "t5", price_type: :bid]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.open == 2000.0
      assert candle.close == 2000.0
    end

    test "creates first candle with :ask price" do
      opts = [data: "xauusd", timeframe: "t5", price_type: :ask]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.open == 2002.0
      assert candle.close == 2002.0
    end

    test "creates first candle with real volume when available" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: false]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick =
        build_tick(~U[2024-01-01 10:00:00Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 10.0,
          ask_volume: 15.0
        )

      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 25.0
    end

    test "creates first candle with nil volume when fake_volume? is false and no volume" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: false]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == nil
    end

    test "creates first candle with fake volume when fake_volume? is true and no volume provided" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: true]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 1.0
    end

    test "creates first candle with real volume when fake_volume? is true and volume is provided" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: true]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick =
        build_tick(~U[2024-01-01 10:00:00Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 10.0,
          ask_volume: 15.0
        )

      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 25.0
    end
  end

  describe "next/2 - updating candle within timeframe" do
    setup do
      opts = [data: "xauusd", timeframe: "t3"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Process first tick
      tick1 = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      %{state: state}
    end

    test "updates candle with second tick", %{state: state} do
      tick2 = build_tick(~U[2024-01-01 10:00:01Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.time == ~U[2024-01-01 10:00:00Z]
      assert candle.open == 2001.0
      assert candle.high == 2004.0
      assert candle.low == 2001.0
      assert candle.close == 2004.0
      assert candle.volume == 2.0

      assert new_state.tick_counter == 2
    end

    test "updates high price correctly", %{state: state} do
      tick2 = build_tick(~U[2024-01-01 10:00:01Z], bid: 2010.0, ask: 2012.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.high == 2011.0
    end

    test "updates low price correctly", %{state: state} do
      tick2 = build_tick(~U[2024-01-01 10:00:01Z], bid: 1990.0, ask: 1992.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.low == 1991.0
    end

    test "accumulates volume when fake_volume? is false" do
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: false]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 =
        build_tick(
          ~U[2024-01-01 10:00:00Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 10.0,
          ask_volume: 15.0
        )

      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 =
        build_tick(~U[2024-01-01 10:00:01Z],
          bid: 2003.0,
          ask: 2005.0,
          bid_volume: 5.0,
          ask_volume: 8.0
        )

      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 38.0
    end

    test "accumulates real volume when fake_volume? is true and volume is provided" do
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: true]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 =
        build_tick(~U[2024-01-01 10:00:00Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 10.0,
          ask_volume: 15.0
        )

      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 =
        build_tick(~U[2024-01-01 10:00:01Z],
          bid: 2003.0,
          ask: 2005.0,
          bid_volume: 5.0,
          ask_volume: 8.0
        )

      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 38.0
    end

    test "increments by 1.0 when fake_volume? is true and no volume provided" do
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: true]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:00:01Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 2.0
    end

    test "mixes fake and real volume when fake_volume? is true" do
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: true]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # First tick without volume -> fake volume = 1.0
      tick1 = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      # Second tick with real volume -> 1.0 + 20.0 = 21.0
      tick2 =
        build_tick(~U[2024-01-01 10:00:01Z],
          bid: 2003.0,
          ask: 2005.0,
          bid_volume: 8.0,
          ask_volume: 12.0
        )

      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 21.0
    end
  end

  describe "next/2 - creating new candle when counter reaches multiplier" do
    test "creates new candle after multiplier ticks" do
      opts = [data: "xauusd", timeframe: "t3"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      ticks = build_tick_sequence(4)

      # Process first 3 ticks
      {event, state} = process_ticks(state, Enum.take(ticks, 3))
      candle = event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:00:00Z]

      # 4th tick should create new candle
      tick4 = Enum.at(ticks, 3)
      event4 = %MarketEvent{data: %{"xauusd" => tick4}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event4, state)

      new_candle = new_event.data["xauusd"]
      assert new_candle.time == ~U[2024-01-01 10:00:03Z]
      assert new_candle.open == new_candle.close
      assert new_state.tick_counter == 1
    end
  end

  describe "next/2 - market_open transition" do
    test "creates new candle when crossing market_open time" do
      opts = [data: "xauusd", timeframe: "t5", market_open: ~T[10:00:00]]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # First tick before market open (counter = 1)
      tick1 = build_tick(~U[2024-01-01 09:59:59Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      # Second tick still before market open (counter = 2)
      tick2 = build_tick(~U[2024-01-01 09:59:59Z], bid: 2001.0, ask: 2003.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, event2_result, state} = TickToCandleProcessor.next(event2, state)

      assert state.tick_counter == 2
      candle_before = event2_result.data["xauusd"]
      assert candle_before.time == ~U[2024-01-01 09:59:59Z]

      # Third tick at or after market open should create new candle
      tick3 = build_tick(~U[2024-01-01 10:00:00Z], bid: 2005.0, ask: 2007.0)
      event3 = %MarketEvent{data: %{"xauusd" => tick3}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event3, state)

      new_candle = new_event.data["xauusd"]
      assert new_candle.time == ~U[2024-01-01 10:00:00Z]
      assert new_state.tick_counter == 1

      # Fourth tick at same time should update the candle
      tick4 = build_tick(~U[2024-01-01 10:00:00Z], bid: 2006.0, ask: 2008.0)
      event4 = %MarketEvent{data: %{"xauusd" => tick4}}
      {:ok, event4_result, state4} = TickToCandleProcessor.next(event4, new_state)

      candle4 = event4_result.data["xauusd"]
      assert candle4.time == ~U[2024-01-01 10:00:00Z]
      assert state4.tick_counter == 2
      assert candle4.close == 2007.0
    end
  end

  describe "next/2 - edge cases" do
    test "handles tick with only bid price" do
      opts = [data: "xauusd", timeframe: "t5"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        bid: 2000.0,
        ask: nil,
        bid_volume: 10.0,
        ask_volume: nil
      }

      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2000.0
    end

    test "handles tick with only ask price" do
      opts = [data: "xauusd", timeframe: "t5"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        bid: nil,
        ask: 2002.0,
        bid_volume: nil,
        ask_volume: 15.0
      }

      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2002.0
    end

    test "raises error when both bid and ask are nil" do
      opts = [data: "xauusd", timeframe: "t5"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        bid: nil,
        ask: nil,
        bid_volume: nil,
        ask_volume: nil
      }

      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert_raise RuntimeError, "Both ask and bid can't be nil", fn ->
        TickToCandleProcessor.next(event, state)
      end
    end

    test "handles mixed volume availability" do
      opts = [data: "xauusd", timeframe: "t2", fake_volume?: false]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # First tick with volume
      tick1 =
        build_tick(~U[2024-01-01 10:00:00Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 10.0,
          ask_volume: 15.0
        )

      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      # Second tick without volume
      tick2 = build_tick(~U[2024-01-01 10:00:01Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      # Should keep the previous volume when new tick has no volume
      assert candle.volume == 25.0
    end
  end

  ## Private test helpers

  defp build_tick(time, opts) do
    bid = Keyword.get(opts, :bid)
    ask = Keyword.get(opts, :ask)
    bid_volume = Keyword.get(opts, :bid_volume)
    ask_volume = Keyword.get(opts, :ask_volume)

    %Tick{
      time: time,
      bid: bid,
      ask: ask,
      bid_volume: bid_volume,
      ask_volume: ask_volume
    }
  end

  defp build_tick_sequence(count) do
    Enum.map(0..(count - 1), fn i ->
      time = DateTime.add(~U[2024-01-01 10:00:00Z], i, :second)
      base_price = 2000.0 + i
      build_tick(time, bid: base_price, ask: base_price + 2.0)
    end)
  end

  defp process_ticks(state, ticks) do
    Enum.reduce(ticks, {nil, state}, fn tick, {_event, acc_state} ->
      event = %MarketEvent{data: %{"xauusd" => tick}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event, acc_state)
      {new_event, new_state}
    end)
  end
end
