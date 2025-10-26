defmodule TheoryCraft.MarketSource.BroadcastStageTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.MarketSource.{
    BroadcastStage,
    DataFeedStage,
    MarketEvent,
    MemoryDataFeed,
    Tick
  }

  alias TheoryCraft.TestHelpers.TestEventConsumer

  @moduletag :capture_log

  ## Setup

  setup_all do
    tick_feed = MemoryDataFeed.new(sample_ticks())

    %{tick_feed: tick_feed}
  end

  ## Tests

  describe "start_link/1" do
    test "successfully starts with subscribe_to option", %{tick_feed: tick_feed} do
      producer = start_producer(tick_feed)

      assert {:ok, broadcast} = BroadcastStage.start_link(subscribe_to: [producer])
      assert is_pid(broadcast)
      assert Process.alive?(broadcast)
    end

    test "successfully starts with custom name", %{tick_feed: tick_feed} do
      producer = start_producer(tick_feed)

      assert {:ok, broadcast} =
               BroadcastStage.start_link(
                 subscribe_to: [producer],
                 name: :test_broadcast_stage
               )

      assert is_pid(broadcast)
      assert Process.whereis(:test_broadcast_stage) == broadcast
    end

    test "raises error when subscribe_to is missing" do
      Process.flag(:trap_exit, true)

      assert {:error, {%KeyError{key: :subscribe_to}, _stacktrace}} =
               BroadcastStage.start_link([])
    end
  end

  describe "broadcasting to multiple consumers" do
    setup %{tick_feed: tick_feed} do
      producer = start_producer(tick_feed)

      {:ok, broadcast} = BroadcastStage.start_link(subscribe_to: [producer])

      %{producer: producer, broadcast: broadcast}
    end

    test "broadcasts all events to each consumer", %{broadcast: broadcast, producer: producer} do
      test_pid = self()

      {:ok, _consumer1} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          tag: :consumer1,
          subscribe_to: [broadcast]
        )

      {:ok, _consumer2} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          tag: :consumer2,
          subscribe_to: [broadcast]
        )

      # Trigger demand AFTER consumers are subscribed
      GenStage.demand(producer, :forward)

      # Collect events from both consumers
      events1 = collect_consumer_events(:consumer1, [])
      events2 = collect_consumer_events(:consumer2, [])

      # Each consumer should receive ALL events (broadcast, not distributed)
      assert length(events1) == length(sample_ticks())
      assert length(events2) == length(sample_ticks())

      # Events should be identical
      assert events1 == events2
    end

    test "passes through events unchanged", %{broadcast: broadcast, producer: producer} do
      test_pid = self()

      {:ok, _consumer} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          subscribe_to: [broadcast]
        )

      # Trigger demand AFTER consumer is subscribed
      GenStage.demand(producer, :forward)

      all_events = collect_all_events([])

      # Should receive all events
      assert length(all_events) == length(sample_ticks())

      # Events should be unchanged MarketEvents with ticks
      for {event, expected_tick} <- Enum.zip(all_events, sample_ticks()) do
        assert %MarketEvent{} = event
        assert event.data["xauusd"] == expected_tick
      end
    end

    test "handles backpressure correctly", %{broadcast: broadcast, producer: producer} do
      test_pid = self()

      # Slow consumer with small demand
      {:ok, _consumer} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          subscribe_to: [{broadcast, min_demand: 1, max_demand: 2}]
        )

      # Trigger demand AFTER consumer is subscribed
      GenStage.demand(producer, :forward)

      # Should receive events in small batches
      assert_receive {:events, events}, 100
      assert length(events) <= 2
    end

    test "broadcasts to three consumers simultaneously", %{
      broadcast: broadcast,
      producer: producer
    } do
      test_pid = self()

      {:ok, _c1} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          tag: :c1,
          subscribe_to: [broadcast]
        )

      {:ok, _c2} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          tag: :c2,
          subscribe_to: [broadcast]
        )

      {:ok, _c3} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          tag: :c3,
          subscribe_to: [broadcast]
        )

      # Trigger demand AFTER consumers are subscribed
      GenStage.demand(producer, :forward)

      events1 = collect_consumer_events(:c1, [])
      events2 = collect_consumer_events(:c2, [])
      events3 = collect_consumer_events(:c3, [])

      # All three should receive identical events
      assert length(events1) == length(sample_ticks())
      assert events1 == events2
      assert events2 == events3
    end
  end

  describe "completion and cancellation" do
    setup %{tick_feed: tick_feed} do
      producer = start_producer(tick_feed)

      {:ok, broadcast} = BroadcastStage.start_link(subscribe_to: [producer])

      %{producer: producer, broadcast: broadcast}
    end

    test "completes when upstream producer completes", %{broadcast: broadcast, producer: producer} do
      test_pid = self()

      {:ok, _consumer} =
        GenStage.start_link(TestEventConsumer,
          test_pid: test_pid,
          subscribe_to: [{broadcast, max_demand: 100}]
        )

      # Trigger demand AFTER consumer is subscribed
      GenStage.demand(producer, :forward)

      # Wait for completion
      all_events = collect_all_events_with_done()

      assert length(all_events) == length(sample_ticks())
    end
  end

  ## Private functions

  defp sample_ticks do
    base_time = ~U[2025-09-04 10:20:00.000Z]

    [
      build_tick(base_time, 0, 2000.0),
      build_tick(base_time, 30, 2001.0),
      build_tick(base_time, 60, 2002.0),
      build_tick(base_time, 90, 2003.0)
    ]
  end

  defp build_tick(base_time, offset_seconds, base_price) do
    %Tick{
      time: DateTime.add(base_time, offset_seconds, :second),
      bid: base_price,
      ask: base_price + 2.0,
      bid_volume: 100.0,
      ask_volume: 150.0
    }
  end

  defp start_producer(feed, name \\ "xauusd") do
    {:ok, producer} = DataFeedStage.start_link({MemoryDataFeed, [from: feed]}, name: name)
    producer
  end

  defp collect_all_events(acc) do
    receive do
      {:events, events} ->
        collect_all_events(acc ++ events)

      {:producer_done, _reason} ->
        acc
    after
      500 -> acc
    end
  end

  defp collect_all_events_with_done do
    collect_all_events_with_done([])
  end

  defp collect_all_events_with_done(acc) do
    receive do
      {:events, events} ->
        collect_all_events_with_done(acc ++ events)

      {:producer_done, :normal} ->
        acc
    after
      1000 -> acc
    end
  end

  defp collect_consumer_events(tag, acc) do
    receive do
      {:events, ^tag, events} ->
        collect_consumer_events(tag, acc ++ events)

      {:producer_done, :normal} ->
        acc
    after
      500 -> acc
    end
  end
end
