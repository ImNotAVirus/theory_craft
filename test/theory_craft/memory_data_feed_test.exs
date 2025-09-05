defmodule TheoryCraft.DataFeeds.MemoryDataFeedTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataFeeds.MemoryDataFeed
  alias TheoryCraft.{Tick, Candle, MarketEvent}

  ## Tests

  describe "new/2" do
    test "creates MemoryDataFeed from enumerable tick data with default precision" do
      market_events = sample_tick_market_events()
      memory_feed = MemoryDataFeed.new(market_events)

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :millisecond
      assert is_reference(memory_feed.table)
    end

    test "creates MemoryDataFeed from enumerable candle data with default precision" do
      market_events = sample_candle_market_events()
      memory_feed = MemoryDataFeed.new(market_events)

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :millisecond
      assert is_reference(memory_feed.table)
    end

    test "creates MemoryDataFeed from enumerable data with custom precision" do
      market_events = sample_tick_market_events()
      memory_feed = MemoryDataFeed.new(market_events, :microsecond)

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :microsecond
      assert is_reference(memory_feed.table)
    end

    test "creates MemoryDataFeed from empty enumerable" do
      memory_feed = MemoryDataFeed.new([])

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :millisecond
    end
  end

  describe "close/1" do
    test "deletes the ETS table" do
      market_events = sample_tick_market_events()
      memory_feed = MemoryDataFeed.new(market_events)

      # Table should exist
      assert :ets.info(memory_feed.table) != :undefined

      # Close should delete the table
      assert :ok = MemoryDataFeed.close(memory_feed)

      # Table should no longer exist
      assert :ets.info(memory_feed.table) == :undefined
    end
  end

  describe "stream/1" do
    test "successfully creates a stream from MemoryDataFeed" do
      memory_feed = MemoryDataFeed.new(sample_tick_market_events())

      assert {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)
      assert Enumerable.impl_for(stream)
    end

    test "requires from option" do
      assert {:error, ":from option is required"} = MemoryDataFeed.stream([])
    end

    test "requires from option to be a MemoryDataFeed" do
      assert {:error, ":from option must be a MemoryDataFeed"} =
               MemoryDataFeed.stream(from: "invalid")
    end
  end

  describe "data streaming" do
    test "streams all tick market events from memory in order" do
      market_events = sample_tick_market_events()
      memory_feed = MemoryDataFeed.new(market_events)

      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)
      streamed_events = Enum.to_list(stream)

      # Should have same number of market events
      assert length(streamed_events) == length(market_events)

      # All items should be MarketEvent structs containing Tick data
      assert Enum.all?(streamed_events, &match?(%MarketEvent{tick_or_candle: %Tick{}}, &1))

      # Should be ordered by time (ETS ordered_set)
      times = Enum.map(streamed_events, & &1.tick_or_candle.time)
      assert times == Enum.sort(times, DateTime)
    end

    test "streams all candle market events from memory in order" do
      market_events = sample_candle_market_events()
      memory_feed = MemoryDataFeed.new(market_events)

      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)
      streamed_events = Enum.to_list(stream)

      # Should have same number of market events
      assert length(streamed_events) == length(market_events)

      # All items should be MarketEvent structs containing Candle data
      assert Enum.all?(streamed_events, &match?(%MarketEvent{tick_or_candle: %Candle{}}, &1))

      # Should be ordered by time (ETS ordered_set)
      times = Enum.map(streamed_events, & &1.tick_or_candle.time)
      assert times == Enum.sort(times, DateTime)
    end

    test "preserves tick data integrity" do
      market_events = sample_tick_market_events()
      memory_feed = MemoryDataFeed.new(market_events)
      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)

      assert Enum.to_list(stream) == market_events
    end

    test "handles different time precisions correctly" do
      market_events = sample_tick_market_events()

      memory_feed = MemoryDataFeed.new(market_events, :microsecond)
      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)

      for {event, original} <- Enum.zip(stream, market_events) do
        assert event.tick_or_candle.time != original.tick_or_candle.time

        assert DateTime.truncate(event.tick_or_candle.time, :millisecond) ==
                 original.tick_or_candle.time
      end
    end

    test "handles empty memory feed" do
      memory_feed = MemoryDataFeed.new([])
      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)

      assert Enum.to_list(stream) == []
    end
  end

  describe "stream!/1" do
    test "returns market events without error tuple when data exists" do
      market_events = sample_tick_market_events()
      memory_feed = MemoryDataFeed.new(market_events)

      stream = MemoryDataFeed.stream!(from: memory_feed)
      streamed_events = Enum.to_list(stream)

      assert length(streamed_events) == length(market_events)
      assert Enum.all?(streamed_events, &match?(%MarketEvent{tick_or_candle: %Tick{}}, &1))
    end
  end

  ## Private functions

  defp sample_tick_market_events do
    base_time = ~U[2025-09-04 10:00:00.000Z]

    [
      %MarketEvent{
        tick_or_candle: %Tick{
          time: DateTime.add(base_time, 0, :second),
          ask: 1.2345,
          bid: 1.2344,
          ask_volume: 1000.0,
          bid_volume: 1500.0
        }
      },
      %MarketEvent{
        tick_or_candle: %Tick{
          time: DateTime.add(base_time, 1, :second),
          ask: 1.2346,
          bid: 1.2345,
          ask_volume: 800.0,
          bid_volume: 1200.0
        }
      },
      %MarketEvent{
        tick_or_candle: %Tick{
          time: DateTime.add(base_time, 2, :second),
          ask: 1.2344,
          bid: 1.2343,
          ask_volume: 1200.0,
          bid_volume: 1800.0
        }
      },
      %MarketEvent{
        tick_or_candle: %Tick{
          time: DateTime.add(base_time, 3, :second),
          ask: 1.2347,
          bid: 1.2346,
          ask_volume: 600.0,
          bid_volume: 900.0
        }
      }
    ]
  end

  defp sample_candle_market_events do
    base_time = ~U[2025-09-04 10:00:00.000Z]

    [
      %MarketEvent{
        tick_or_candle: %Candle{
          time: DateTime.add(base_time, 0, :minute),
          open: 1.2340,
          high: 1.2350,
          low: 1.2338,
          close: 1.2345,
          volume: 5000.0
        }
      },
      %MarketEvent{
        tick_or_candle: %Candle{
          time: DateTime.add(base_time, 1, :minute),
          open: 1.2345,
          high: 1.2355,
          low: 1.2342,
          close: 1.2350,
          volume: 4800.0
        }
      }
    ]
  end
end
