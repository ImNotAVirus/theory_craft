defmodule TheoryCraft.DataFeeds.MemoryDataFeedTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataFeeds.MemoryDataFeed
  alias TheoryCraft.{Tick, Candle}

  ## Tests

  describe "new/2" do
    test "creates MemoryDataFeed from enumerable tick data with default precision" do
      memory_feed = MemoryDataFeed.new(sample_ticks())

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :millisecond
      assert is_reference(memory_feed.table)
    end

    test "creates MemoryDataFeed from enumerable candle data with default precision" do
      memory_feed = MemoryDataFeed.new(sample_candles())

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :millisecond
      assert is_reference(memory_feed.table)
    end

    test "creates MemoryDataFeed from enumerable data with custom precision" do
      ticks = sample_ticks()
      memory_feed = MemoryDataFeed.new(ticks, :microsecond)

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :microsecond
      assert is_reference(memory_feed.table)
    end

    test "creates MemoryDataFeed with auto precision detection" do
      # Test with millisecond precision data
      ticks_ms = sample_ticks()
      memory_feed_ms = MemoryDataFeed.new(ticks_ms, :auto)

      assert %MemoryDataFeed{} = memory_feed_ms
      assert memory_feed_ms.precision == :millisecond

      # Test with microsecond precision data
      ticks_us = sample_ticks_microsecond()
      memory_feed_us = MemoryDataFeed.new(ticks_us, :auto)

      assert %MemoryDataFeed{} = memory_feed_us
      assert memory_feed_us.precision == :microsecond

      # Test with second precision data
      ticks_sec = sample_ticks_second()
      memory_feed_sec = MemoryDataFeed.new(ticks_sec, :auto)

      assert %MemoryDataFeed{} = memory_feed_sec
      assert memory_feed_sec.precision == :second
    end

    test "creates MemoryDataFeed from empty enumerable" do
      memory_feed = MemoryDataFeed.new([])

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :millisecond
    end
  end

  describe "close/1" do
    test "deletes the ETS table" do
      memory_feed = MemoryDataFeed.new(sample_ticks())

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
      memory_feed = MemoryDataFeed.new(sample_ticks())

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
    test "streams all tick data from memory in order" do
      ticks = sample_ticks()
      memory_feed = MemoryDataFeed.new(ticks)

      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)
      streamed_ticks = Enum.to_list(stream)

      for {streamed_tick, original_tick} <- Enum.zip(streamed_ticks, ticks) do
        assert streamed_tick == original_tick
      end
    end

    test "streams all candle data from memory in order" do
      candles = sample_candles()
      memory_feed = MemoryDataFeed.new(candles)

      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)
      streamed_candles = Enum.to_list(stream)

      for {streamed_candle, original_candle} <- Enum.zip(streamed_candles, candles) do
        assert streamed_candle == original_candle
      end
    end

    test "handles different time precisions correctly" do
      ticks = sample_ticks()

      memory_feed = MemoryDataFeed.new(ticks, :microsecond)
      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)

      streamed_ticks = Enum.to_list(stream)

      for {tick, original} <- Enum.zip(streamed_ticks, ticks) do
        # Microsecond precision should be different from original millisecond precision
        assert tick.time != original.time

        # But when truncated to millisecond, they should match
        assert DateTime.truncate(tick.time, :millisecond) == original.time
      end
    end

    test "handles empty memory feed" do
      memory_feed = MemoryDataFeed.new([])
      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)

      assert Enum.to_list(stream) == []
    end
  end

  describe "stream!/1" do
    test "returns ticks without error tuple when data exists" do
      ticks = sample_ticks()
      memory_feed = MemoryDataFeed.new(ticks)

      stream = MemoryDataFeed.stream!(from: memory_feed)
      streamed_ticks = Enum.to_list(stream)

      for {streamed_tick, original_tick} <- Enum.zip(streamed_ticks, ticks) do
        assert streamed_tick == original_tick
      end
    end
  end

  ## Private functions

  defp sample_ticks() do
    base_time = ~U[2025-09-04 10:00:00.000Z]

    [
      %Tick{
        time: DateTime.add(base_time, 0, :second),
        ask: 1.2345,
        bid: 1.2344,
        ask_volume: 1000.0,
        bid_volume: 1500.0
      },
      %Tick{
        time: DateTime.add(base_time, 1, :second),
        ask: 1.2346,
        bid: 1.2345,
        ask_volume: 800.0,
        bid_volume: 1200.0
      },
      %Tick{
        time: DateTime.add(base_time, 2, :second),
        ask: 1.2344,
        bid: 1.2343,
        ask_volume: 1200.0,
        bid_volume: 1800.0
      },
      %Tick{
        time: DateTime.add(base_time, 3, :second),
        ask: 1.2347,
        bid: 1.2346,
        ask_volume: 600.0,
        bid_volume: 900.0
      }
    ]
  end

  defp sample_candles() do
    base_time = ~U[2025-09-04 10:00:00.000Z]

    [
      %Candle{
        time: DateTime.add(base_time, 0, :minute),
        open: 1.2340,
        high: 1.2350,
        low: 1.2338,
        close: 1.2345,
        volume: 5000.0
      },
      %Candle{
        time: DateTime.add(base_time, 1, :minute),
        open: 1.2345,
        high: 1.2355,
        low: 1.2342,
        close: 1.2350,
        volume: 4800.0
      }
    ]
  end

  defp sample_ticks_microsecond() do
    # 6 digits for microsecond precision
    base_time = ~U[2025-09-04 10:00:00.123456Z]

    [
      %Tick{
        time: DateTime.add(base_time, 0, :second),
        ask: 1.2345,
        bid: 1.2344,
        ask_volume: 1000.0,
        bid_volume: 1500.0
      }
    ]
  end

  defp sample_ticks_second() do
    # No microseconds for second precision
    base_time = ~U[2025-09-04 10:00:00Z]

    [
      %Tick{
        time: base_time,
        ask: 1.2345,
        bid: 1.2344,
        ask_volume: 1000.0,
        bid_volume: 1500.0
      }
    ]
  end
end
