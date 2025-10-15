defmodule TheoryCraft.Processors.TickToCandleProcessorTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.{Candle, MarketEvent, Tick}
  alias TheoryCraft.Processors.TickToCandleProcessor

  ## Tests

  describe "init/1" do
    test "initializes with required options" do
      opts = [data: "xauusd", timeframe: "t5", name: "xauusd"]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert %TickToCandleProcessor{} = state
      assert state.data_name == "xauusd"
      assert state.timeframe == {"t", 5}
      assert state.name == "xauusd"
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
      opts = [data: "xauusd", timeframe: "t5", price_type: :bid, name: "xauusd"]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.price_type == :bid
    end

    test "initializes with custom price_type :ask" do
      opts = [data: "xauusd", timeframe: "t5", price_type: :ask, name: "xauusd"]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.price_type == :ask
    end

    test "initializes with fake_volume? false" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: false, name: "xauusd"]

      assert {:ok, state} = TickToCandleProcessor.init(opts)
      assert state.fake_volume? == false
    end

    test "initializes with custom market_open" do
      opts = [data: "xauusd", timeframe: "t5", market_open: ~T[09:30:00], name: "xauusd"]

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
      opts = [data: "xauusd", timeframe: "t5", name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t5", price_type: :bid, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.open == 2000.0
      assert candle.close == 2000.0
    end

    test "creates first candle with :ask price" do
      opts = [data: "xauusd", timeframe: "t5", price_type: :ask, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.open == 2002.0
      assert candle.close == 2002.0
    end

    test "creates first candle with real volume when available" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: false, name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: false, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == nil
    end

    test "creates first candle with fake volume when fake_volume? is true and no volume provided" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: true, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      assert %MarketEvent{data: %{"xauusd" => candle}} = new_event
      assert candle.volume == 1.0
    end

    test "creates first candle with real volume when fake_volume? is true and volume is provided" do
      opts = [data: "xauusd", timeframe: "t5", fake_volume?: true, name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t3", name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: false, name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: true, name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: true, name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t3", fake_volume?: true, name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t3", name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t5", market_open: ~T[10:00:00], name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t5", name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t5", name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t5", name: "xauusd"]
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
      opts = [data: "xauusd", timeframe: "t2", fake_volume?: false, name: "xauusd"]
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

  describe "next/2 - monthly timeframes" do
    test "creates first candle aligned on first of month" do
      opts = [data: "xauusd", timeframe: "M", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Tick on Jan 17 should align to Jan 1
      tick = build_tick(~U[2024-01-17 15:45:30Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 09:30:00Z]
      assert candle.open == 2001.0
      assert new_state.next_time == ~U[2024-02-01 09:30:00Z]
    end

    test "updates candle within same month" do
      opts = [data: "xauusd", timeframe: "M", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-05 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-25 18:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 00:00:00Z]
      assert candle.open == 2001.0
      assert candle.close == 2004.0
      assert new_state.next_time == ~U[2024-02-01 00:00:00Z]
    end

    test "creates new candle on next month" do
      opts = [data: "xauusd", timeframe: "M", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-20 15:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-02-10 12:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-02-01 09:30:00Z]
      assert candle.open == 2004.0
      assert new_state.next_time == ~U[2024-03-01 09:30:00Z]
    end

    test "handles M with multiplier > 1" do
      opts = [data: "xauusd", timeframe: "M3", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-17 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 00:00:00Z]
      assert new_state.next_time == ~U[2024-04-01 00:00:00Z]
    end

    test "handles month overflow (Jan 31 to Feb)" do
      opts = [data: "xauusd", timeframe: "M", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-31 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-02-15 10:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-02-01 00:00:00Z]
      # Feb has 29 days in 2024 (leap year), but we start on 1st
      assert new_state.next_time == ~U[2024-03-01 00:00:00Z]
    end

    test "accumulates volume with fake_volume?" do
      opts = [data: "xauusd", timeframe: "M", fake_volume?: true, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-10 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-20 15:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 2.0
    end

    test "handles different price types" do
      opts = [data: "xauusd", timeframe: "M", price_type: :bid, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-17 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2000.0
    end
  end

  describe "next/2 - weekly timeframes" do
    test "creates first candle aligned on Monday market_open by default" do
      opts = [data: "xauusd", timeframe: "W", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # 2024-01-17 is a Wednesday, should align to Monday 2024-01-15
      tick = build_tick(~U[2024-01-17 15:45:30Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-15 09:30:00Z]
      assert candle.open == 2001.0
      assert new_state.next_time == ~U[2024-01-22 09:30:00Z]
    end

    test "creates first candle aligned on Sunday when weekly_open: :sunday" do
      opts = [
        data: "xauusd",
        timeframe: "W",
        weekly_open: :sunday,
        market_open: ~T[00:00:00],
        name: "xauusd"
      ]

      {:ok, state} = TickToCandleProcessor.init(opts)

      # 2024-01-17 is a Wednesday, should align to Sunday 2024-01-14
      tick = build_tick(~U[2024-01-17 15:45:30Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-14 00:00:00Z]
      assert candle.open == 2001.0
      assert new_state.next_time == ~U[2024-01-21 00:00:00Z]
    end

    test "updates candle within same week" do
      opts = [data: "xauusd", timeframe: "W", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-15 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-19 18:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-15 00:00:00Z]
      assert candle.open == 2001.0
      assert candle.close == 2004.0
      assert new_state.next_time == ~U[2024-01-22 00:00:00Z]
    end

    test "creates new candle on next week" do
      opts = [data: "xauusd", timeframe: "W", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-17 15:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-23 12:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-22 09:30:00Z]
      assert candle.open == 2004.0
      assert new_state.next_time == ~U[2024-01-29 09:30:00Z]
    end

    test "handles W with multiplier > 1" do
      opts = [data: "xauusd", timeframe: "W2", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-17 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-15 00:00:00Z]
      assert new_state.next_time == ~U[2024-01-29 00:00:00Z]
    end

    test "accumulates volume with fake_volume?" do
      opts = [data: "xauusd", timeframe: "W", fake_volume?: true, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-15 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-18 15:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 2.0
    end

    test "handles different price types" do
      opts = [data: "xauusd", timeframe: "W", price_type: :ask, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-17 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2002.0
    end
  end

  describe "next/2 - daily timeframes" do
    test "creates first candle aligned on market_open" do
      opts = [data: "xauusd", timeframe: "D", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Tick at 15:45 should align to 09:30:00 same day
      tick = build_tick(~U[2024-01-15 15:45:30Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-15 09:30:00Z]
      assert candle.open == 2001.0
      assert new_state.next_time == ~U[2024-01-16 09:30:00Z]
    end

    test "updates candle within same day" do
      opts = [data: "xauusd", timeframe: "D", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-15 10:30:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-15 18:45:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-15 00:00:00Z]
      assert candle.open == 2001.0
      assert candle.close == 2004.0
      assert candle.high == 2004.0
      assert new_state.next_time == ~U[2024-01-16 00:00:00Z]
    end

    test "creates new candle on next day" do
      opts = [data: "xauusd", timeframe: "D", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-15 15:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-16 12:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-16 09:30:00Z]
      assert candle.open == 2004.0
      assert new_state.next_time == ~U[2024-01-17 09:30:00Z]
    end

    test "handles D with multiplier > 1" do
      opts = [data: "xauusd", timeframe: "D3", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-15 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-15 00:00:00Z]
      assert new_state.next_time == ~U[2024-01-18 00:00:00Z]
    end

    test "accumulates volume with fake_volume?" do
      opts = [data: "xauusd", timeframe: "D", fake_volume?: true, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-15 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-15 15:00:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 2.0
    end

    test "handles different price types" do
      opts = [data: "xauusd", timeframe: "D", price_type: :bid, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-15 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2000.0
    end
  end

  describe "next/2 - hour-based timeframes" do
    test "creates first candle with aligned time" do
      opts = [data: "xauusd", timeframe: "h4", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Tick at 11:23:45 should align to 08:00:00 for h4
      tick = build_tick(~U[2024-01-01 11:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 08:00:00Z]
      assert candle.open == 2001.0
      assert new_state.next_time == ~U[2024-01-01 12:00:00Z]
    end

    test "updates candle within same timeframe period" do
      opts = [data: "xauusd", timeframe: "h1", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:17:30Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:45:15Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:00:00Z]
      assert candle.open == 2001.0
      assert candle.close == 2004.0
      assert candle.high == 2004.0
      assert new_state.next_time == ~U[2024-01-01 11:00:00Z]
    end

    test "creates new candle when crossing timeframe boundary" do
      opts = [data: "xauusd", timeframe: "h4", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:30:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 14:15:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 12:00:00Z]
      assert candle.open == 2004.0
      assert candle.close == 2004.0
      assert new_state.next_time == ~U[2024-01-01 16:00:00Z]
    end

    test "handles h1 (1 hour) timeframe" do
      opts = [data: "xauusd", timeframe: "h1", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:00:00Z]
      assert new_state.next_time == ~U[2024-01-01 11:00:00Z]
    end

    test "accumulates volume with fake_volume?" do
      opts = [data: "xauusd", timeframe: "h1", fake_volume?: true, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:12:30Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:45:00Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 2.0
    end

    test "accumulates real volume when provided" do
      opts = [data: "xauusd", timeframe: "h1", fake_volume?: false, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 =
        build_tick(~U[2024-01-01 10:12:30Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 20.0,
          ask_volume: 30.0
        )

      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 =
        build_tick(~U[2024-01-01 10:45:00Z],
          bid: 2003.0,
          ask: 2005.0,
          bid_volume: 15.0,
          ask_volume: 25.0
        )

      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 90.0
    end

    test "handles :bid price type" do
      opts = [data: "xauusd", timeframe: "h1", price_type: :bid, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2000.0
    end

    test "handles :ask price type" do
      opts = [data: "xauusd", timeframe: "h1", price_type: :ask, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2002.0
    end
  end

  describe "next/2 - minute-based timeframes" do
    test "creates first candle with aligned time" do
      opts = [data: "xauusd", timeframe: "m5", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Tick at 10:23:45 should align to 10:20:00 for m5
      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:20:00Z]
      assert candle.open == 2001.0
      assert new_state.next_time == ~U[2024-01-01 10:25:00Z]
    end

    test "updates candle within same timeframe period" do
      opts = [data: "xauusd", timeframe: "m15", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:17:30Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:22:15Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:15:00Z]
      assert candle.open == 2001.0
      assert candle.close == 2004.0
      assert candle.high == 2004.0
      assert new_state.next_time == ~U[2024-01-01 10:30:00Z]
    end

    test "creates new candle when crossing timeframe boundary" do
      opts = [data: "xauusd", timeframe: "m5", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:22:30Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:27:15Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:25:00Z]
      assert candle.open == 2004.0
      assert candle.close == 2004.0
      assert new_state.next_time == ~U[2024-01-01 10:30:00Z]
    end

    test "handles m1 (1 minute) timeframe" do
      opts = [data: "xauusd", timeframe: "m1", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:23:00Z]
      assert new_state.next_time == ~U[2024-01-01 10:24:00Z]
    end

    test "accumulates volume with fake_volume?" do
      opts = [data: "xauusd", timeframe: "m5", fake_volume?: true, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:12:30Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:14:45Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 2.0
    end

    test "accumulates real volume when provided" do
      opts = [data: "xauusd", timeframe: "m5", fake_volume?: false, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 =
        build_tick(~U[2024-01-01 10:12:30Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 100.0,
          ask_volume: 150.0
        )

      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 =
        build_tick(~U[2024-01-01 10:14:45Z],
          bid: 2003.0,
          ask: 2005.0,
          bid_volume: 50.0,
          ask_volume: 75.0
        )

      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 375.0
    end

    test "handles :bid price type" do
      opts = [data: "xauusd", timeframe: "m5", price_type: :bid, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2000.0
    end

    test "handles :ask price type" do
      opts = [data: "xauusd", timeframe: "m5", price_type: :ask, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2002.0
    end
  end

  describe "next/2 - second-based timeframes" do
    test "creates first candle with aligned time" do
      opts = [data: "xauusd", timeframe: "s5", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Tick at 10:00:23 should align to 10:00:20 for s5
      tick = build_tick(~U[2024-01-01 10:00:23Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:00:20Z]
      assert candle.open == 2001.0
      assert new_state.next_time == ~U[2024-01-01 10:00:25Z]
    end

    test "updates candle within same timeframe period" do
      opts = [data: "xauusd", timeframe: "s10", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:00:12Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:00:15Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:00:10Z]
      assert candle.open == 2001.0
      assert candle.close == 2004.0
      assert candle.high == 2004.0
      assert new_state.next_time == ~U[2024-01-01 10:00:20Z]
    end

    test "creates new candle when crossing timeframe boundary" do
      opts = [data: "xauusd", timeframe: "s5", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:00:22Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:00:27Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.time == ~U[2024-01-01 10:00:25Z]
      assert candle.open == 2004.0
      assert candle.close == 2004.0
      assert new_state.next_time == ~U[2024-01-01 10:00:30Z]
    end

    test "handles :bid price type" do
      opts = [data: "xauusd", timeframe: "s15", price_type: :bid, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:23Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2000.0
    end

    test "handles :ask price type" do
      opts = [data: "xauusd", timeframe: "s30", price_type: :ask, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:23Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      assert candle.open == 2002.0
    end

    test "accumulates volume with fake_volume? true" do
      opts = [data: "xauusd", timeframe: "s5", fake_volume?: true, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 = build_tick(~U[2024-01-01 10:00:12Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 = build_tick(~U[2024-01-01 10:00:14Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 2.0
    end

    test "accumulates real volume when provided" do
      opts = [data: "xauusd", timeframe: "s5", fake_volume?: false, name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick1 =
        build_tick(~U[2024-01-01 10:00:12Z],
          bid: 2000.0,
          ask: 2002.0,
          bid_volume: 10.0,
          ask_volume: 15.0
        )

      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      tick2 =
        build_tick(~U[2024-01-01 10:00:14Z],
          bid: 2003.0,
          ask: 2005.0,
          bid_volume: 5.0,
          ask_volume: 8.0
        )

      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, _new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      assert candle.volume == 38.0
    end
  end

  describe "next/2 - different timezones support" do
    test "handles daily timeframe with Europe/Paris timezone" do
      opts = [data: "xauusd", timeframe: "D", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Create a tick in Europe/Paris timezone
      {:ok, paris_time} = DateTime.new(~D[2024-01-15], ~T[15:45:30], "Europe/Paris")
      tick = build_tick(paris_time, bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      # Should align to market_open on the same day in Europe/Paris
      assert candle.time.time_zone == "Europe/Paris"
      assert DateTime.to_date(candle.time) == ~D[2024-01-15]
      assert DateTime.to_time(candle.time) == ~T[09:30:00]
      assert candle.open == 2001.0

      # Next time should also be in Europe/Paris
      assert new_state.next_time.time_zone == "Europe/Paris"
      assert DateTime.to_date(new_state.next_time) == ~D[2024-01-16]
      assert DateTime.to_time(new_state.next_time) == ~T[09:30:00]
    end

    test "handles weekly timeframe with America/New_York timezone" do
      opts = [data: "xauusd", timeframe: "W", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # 2024-01-17 is a Wednesday, should align to Monday 2024-01-15
      {:ok, ny_time} = DateTime.new(~D[2024-01-17], ~T[15:45:30], "America/New_York")
      tick = build_tick(ny_time, bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      # Should align to Monday market_open in America/New_York
      assert candle.time.time_zone == "America/New_York"
      assert DateTime.to_date(candle.time) == ~D[2024-01-15]
      assert DateTime.to_time(candle.time) == ~T[09:30:00]
      assert candle.open == 2001.0

      # Next time should be next Monday in America/New_York
      assert new_state.next_time.time_zone == "America/New_York"
      assert DateTime.to_date(new_state.next_time) == ~D[2024-01-22]
      assert DateTime.to_time(new_state.next_time) == ~T[09:30:00]
    end

    test "handles monthly timeframe with Europe/Paris timezone" do
      opts = [data: "xauusd", timeframe: "M", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # Tick on Jan 17 should align to Jan 1 in Europe/Paris
      {:ok, paris_time} = DateTime.new(~D[2024-01-17], ~T[15:45:30], "Europe/Paris")
      tick = build_tick(paris_time, bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, new_state} = TickToCandleProcessor.next(event, state)

      candle = new_event.data["xauusd"]
      # Should align to first of month + market_open in Europe/Paris
      assert candle.time.time_zone == "Europe/Paris"
      assert DateTime.to_date(candle.time) == ~D[2024-01-01]
      assert DateTime.to_time(candle.time) == ~T[09:30:00]
      assert candle.open == 2001.0

      # Next time should be next month in Europe/Paris
      assert new_state.next_time.time_zone == "Europe/Paris"
      assert DateTime.to_date(new_state.next_time) == ~D[2024-02-01]
      assert DateTime.to_time(new_state.next_time) == ~T[09:30:00]
    end

    test "handles crossing month boundary with America/New_York timezone" do
      opts = [data: "xauusd", timeframe: "M", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # First tick in January
      {:ok, ny_time1} = DateTime.new(~D[2024-01-20], ~T[15:00:00], "America/New_York")
      tick1 = build_tick(ny_time1, bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      # Second tick in February
      {:ok, ny_time2} = DateTime.new(~D[2024-02-10], ~T[12:00:00], "America/New_York")
      tick2 = build_tick(ny_time2, bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      # New candle should be in February in America/New_York timezone
      assert candle.time.time_zone == "America/New_York"
      assert DateTime.to_date(candle.time) == ~D[2024-02-01]
      assert DateTime.to_time(candle.time) == ~T[00:00:00]
      assert candle.open == 2004.0

      # Next time should be March in America/New_York
      assert new_state.next_time.time_zone == "America/New_York"
      assert DateTime.to_date(new_state.next_time) == ~D[2024-03-01]
    end

    test "preserves timezone across candle updates" do
      opts = [data: "xauusd", timeframe: "D", market_open: ~T[00:00:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # First tick creates candle
      {:ok, paris_time1} = DateTime.new(~D[2024-01-15], ~T[10:30:00], "Europe/Paris")
      tick1 = build_tick(paris_time1, bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      # Second tick updates same candle
      {:ok, paris_time2} = DateTime.new(~D[2024-01-15], ~T[18:45:00], "Europe/Paris")
      tick2 = build_tick(paris_time2, bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      # Candle time should still be in Europe/Paris
      assert candle.time.time_zone == "Europe/Paris"
      assert DateTime.to_date(candle.time) == ~D[2024-01-15]
      assert candle.open == 2001.0
      assert candle.close == 2004.0

      # Next time should still be in Europe/Paris
      assert new_state.next_time.time_zone == "Europe/Paris"
      assert DateTime.to_date(new_state.next_time) == ~D[2024-01-16]
    end

    test "handles DST transitions correctly" do
      opts = [data: "xauusd", timeframe: "D", market_open: ~T[09:30:00], name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # March 31, 2024 is DST transition in Europe/Paris (UTC+1 -> UTC+2)
      {:ok, before_dst} = DateTime.new(~D[2024-03-31], ~T[15:00:00], "Europe/Paris")
      tick1 = build_tick(before_dst, bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"xauusd" => tick1}}
      {:ok, _event, state} = TickToCandleProcessor.next(event1, state)

      # April 1, 2024 is after DST transition
      {:ok, after_dst} = DateTime.new(~D[2024-04-01], ~T[12:00:00], "Europe/Paris")
      tick2 = build_tick(after_dst, bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"xauusd" => tick2}}
      {:ok, new_event, new_state} = TickToCandleProcessor.next(event2, state)

      candle = new_event.data["xauusd"]
      # Should handle DST correctly, timezone preserved
      assert candle.time.time_zone == "Europe/Paris"
      assert DateTime.to_date(candle.time) == ~D[2024-04-01]
      assert DateTime.to_time(candle.time) == ~T[09:30:00]

      assert new_state.next_time.time_zone == "Europe/Paris"
      assert DateTime.to_date(new_state.next_time) == ~D[2024-04-02]
    end
  end

  describe "next/2 - output name vs input data" do
    test "writes candles to 'name' key, not 'data' key (tick timeframe)" do
      opts = [data: "xauusd_ticks", timeframe: "t3", name: "xauusd_t3"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd_ticks" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      # Input ticks should still be present
      assert %Tick{} = new_event.data["xauusd_ticks"]

      # Output candles should be in the name key
      assert %Candle{} = new_event.data["xauusd_t3"]
      assert new_event.data["xauusd_t3"].open == 2001.0
    end

    test "writes candles to 'name' key, not 'data' key (minute timeframe)" do
      opts = [data: "eurusd_ticks", timeframe: "m5", name: "eurusd_m5"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 1.0850, ask: 1.0852)
      event = %MarketEvent{data: %{"eurusd_ticks" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      # Input ticks should still be present
      assert %Tick{} = new_event.data["eurusd_ticks"]

      # Output candles should be in the name key
      assert %Candle{} = new_event.data["eurusd_m5"]
      assert new_event.data["eurusd_m5"].time == ~U[2024-01-01 10:20:00Z]
      assert new_event.data["eurusd_m5"].open == 1.0851
    end

    test "uses default name when not specified" do
      opts = [data: "btcusd", timeframe: "h1"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      assert state.name == "btcusd_h1"

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 50000.0, ask: 50010.0)
      event = %MarketEvent{data: %{"btcusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      # Input ticks should still be present
      assert %Tick{} = new_event.data["btcusd"]

      # Output candles should be in the default name key
      assert %Candle{} = new_event.data["btcusd_h1"]
    end

    test "preserves both tick and candle data across updates" do
      opts = [data: "gold_ticks", timeframe: "t2", name: "gold_t2"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      # First tick
      tick1 = build_tick(~U[2024-01-01 10:00:00Z], bid: 2000.0, ask: 2002.0)
      event1 = %MarketEvent{data: %{"gold_ticks" => tick1}}
      {:ok, event_after_first, state} = TickToCandleProcessor.next(event1, state)

      # Both should be present
      assert %Tick{} = event_after_first.data["gold_ticks"]
      assert %Candle{} = event_after_first.data["gold_t2"]

      # Second tick (updates candle)
      tick2 = build_tick(~U[2024-01-01 10:00:01Z], bid: 2003.0, ask: 2005.0)
      event2 = %MarketEvent{data: %{"gold_ticks" => tick2}}
      {:ok, event_after_second, _state} = TickToCandleProcessor.next(event2, state)

      # Both should still be present
      assert %Tick{} = event_after_second.data["gold_ticks"]
      assert event_after_second.data["gold_ticks"].bid == 2003.0

      assert %Candle{} = event_after_second.data["gold_t2"]
      assert event_after_second.data["gold_t2"].close == 2004.0
    end

    test "works with daily timeframe" do
      opts = [data: "spy_ticks", timeframe: "D", name: "spy_daily", market_open: ~T[09:30:00]]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-15 15:45:30Z], bid: 480.0, ask: 480.5)
      event = %MarketEvent{data: %{"spy_ticks" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      # Both should be present
      assert %Tick{} = new_event.data["spy_ticks"]
      assert %Candle{} = new_event.data["spy_daily"]
      assert new_event.data["spy_daily"].time == ~U[2024-01-15 09:30:00Z]
    end

    test "allows same value for data and name (overwrites input)" do
      opts = [data: "xauusd", timeframe: "m5", name: "xauusd"]
      {:ok, state} = TickToCandleProcessor.init(opts)

      tick = build_tick(~U[2024-01-01 10:23:45Z], bid: 2000.0, ask: 2002.0)
      event = %MarketEvent{data: %{"xauusd" => tick}}

      assert {:ok, new_event, _new_state} = TickToCandleProcessor.next(event, state)

      # Should have overwritten the tick with the candle
      assert %Candle{} = new_event.data["xauusd"]
      refute match?(%Tick{}, new_event.data["xauusd"])
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
