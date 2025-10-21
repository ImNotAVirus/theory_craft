defmodule TheoryCraft.DataFeeds.MemoryDataFeedTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataFeeds.MemoryDataFeed
  alias TheoryCraft.{Tick, Bar}

  ## Setup

  setup_all do
    # Create shared data feeds for tests
    # Note: async: true means each test runs in its own process,
    # but they can all read from the same ETS tables created here
    ticks = sample_ticks()
    bars = sample_bars()
    ticks_us = sample_ticks_microsecond()
    ticks_sec = sample_ticks_second()

    tick_feed = MemoryDataFeed.new(ticks)
    bar_feed = MemoryDataFeed.new(bars)
    tick_feed_us = MemoryDataFeed.new(ticks_us, :microsecond)
    tick_feed_sec = MemoryDataFeed.new(ticks_sec, :auto)

    %{
      ticks: ticks,
      bars: bars,
      ticks_us: ticks_us,
      ticks_sec: ticks_sec,
      tick_feed: tick_feed,
      bar_feed: bar_feed,
      tick_feed_us: tick_feed_us,
      tick_feed_sec: tick_feed_sec
    }
  end

  ## Tests

  describe "new/2" do
    test "creates MemoryDataFeed from enumerable tick data with default precision" do
      memory_feed = MemoryDataFeed.new(sample_ticks())

      assert %MemoryDataFeed{} = memory_feed
      assert memory_feed.precision == :millisecond
      assert is_reference(memory_feed.table)
    end

    test "creates MemoryDataFeed from enumerable bar data with default precision" do
      memory_feed = MemoryDataFeed.new(sample_bars())

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
    test "streams all tick data from memory in order", %{tick_feed: tick_feed, ticks: ticks} do
      {:ok, stream} = MemoryDataFeed.stream(from: tick_feed)
      streamed_ticks = Enum.to_list(stream)

      for {streamed_tick, original_tick} <- Enum.zip(streamed_ticks, ticks) do
        assert streamed_tick == original_tick
      end
    end

    test "streams all bar data from memory in order", %{
      bar_feed: bar_feed,
      bars: bars
    } do
      {:ok, stream} = MemoryDataFeed.stream(from: bar_feed)
      streamed_bars = Enum.to_list(stream)

      for {streamed_bar, original_bar} <- Enum.zip(streamed_bars, bars) do
        assert streamed_bar == original_bar
      end
    end

    test "handles different time precisions correctly", %{
      tick_feed_us: tick_feed_us,
      ticks_us: ticks_us
    } do
      {:ok, stream} = MemoryDataFeed.stream(from: tick_feed_us)
      streamed_ticks = Enum.to_list(stream)

      for {tick, original} <- Enum.zip(streamed_ticks, ticks_us) do
        # Microsecond precision should preserve the original time
        assert tick.time == original.time
      end
    end

    test "handles empty memory feed" do
      memory_feed = MemoryDataFeed.new([])
      {:ok, stream} = MemoryDataFeed.stream(from: memory_feed)

      assert Enum.to_list(stream) == []
    end
  end

  describe "stream!/1" do
    test "returns ticks without error tuple when data exists", %{
      tick_feed: tick_feed,
      ticks: ticks
    } do
      stream = MemoryDataFeed.stream!(from: tick_feed)
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

  defp sample_bars() do
    base_time = ~U[2025-09-04 10:00:00.000Z]

    [
      %Bar{
        time: DateTime.add(base_time, 0, :minute),
        open: 1.2340,
        high: 1.2350,
        low: 1.2338,
        close: 1.2345,
        volume: 5000.0
      },
      %Bar{
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
