defmodule TheoryCraft.MarketSource.AggregatorStageTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.MarketSource.AggregatorStage
  alias TheoryCraft.MarketSource.MarketEvent
  alias TheoryCraft.TestHelpers
  alias TheoryCraft.TestHelpers.ManualProducer
  alias TheoryCraft.TestHelpers.TestEventConsumer

  @moduletag :capture_log

  ## Tests

  describe "AggregatorStage synchronization" do
    test "synchronizes events from 2 parallel producers" do
      # Start aggregator
      {:ok, aggregator} =
        AggregatorStage.start_link(
          producer_count: 2,
          max_demand: 10
        )

      # Create 2 manual producers
      {:ok, producer1} = GenStage.start_link(ManualProducer, %{events: []})
      {:ok, producer2} = GenStage.start_link(ManualProducer, %{events: []})

      # Subscribe aggregator to both producers
      GenStage.sync_subscribe(aggregator, to: producer1, cancel: :transient, index: 0)
      GenStage.sync_subscribe(aggregator, to: producer2, cancel: :transient, index: 1)

      # Create test consumer
      {:ok, consumer} = GenStage.start_link(TestEventConsumer, test_pid: self())
      GenStage.sync_subscribe(consumer, to: aggregator)

      # Send events from producer1
      TestHelpers.send_events(producer1, [
        %MarketEvent{data: %{"p1" => 1}},
        %MarketEvent{data: %{"p1" => 2}},
        %MarketEvent{data: %{"p1" => 3}}
      ])

      # Send events from producer2
      TestHelpers.send_events(producer2, [
        %MarketEvent{data: %{"p2" => :a}},
        %MarketEvent{data: %{"p2" => :b}}
      ])

      # Should receive 2 merged events (min of 3 and 2)
      assert_receive {:events, events}, 1000
      assert length(events) == 2

      # First merged event
      assert %MarketEvent{data: %{"p1" => 1, "p2" => :a}} = Enum.at(events, 0)
      # Second merged event
      assert %MarketEvent{data: %{"p1" => 2, "p2" => :b}} = Enum.at(events, 1)

      # Send more from producer2 to complete the third
      TestHelpers.send_events(producer2, [%MarketEvent{data: %{"p2" => :c}}])

      assert_receive {:events, events}, 1000
      assert length(events) == 1
      assert %MarketEvent{data: %{"p1" => 3, "p2" => :c}} = Enum.at(events, 0)
    end

    test "synchronizes events from 3 parallel producers" do
      {:ok, aggregator} =
        AggregatorStage.start_link(
          producer_count: 3,
          max_demand: 10
        )

      {:ok, p1} = GenStage.start_link(ManualProducer, %{events: []})
      {:ok, p2} = GenStage.start_link(ManualProducer, %{events: []})
      {:ok, p3} = GenStage.start_link(ManualProducer, %{events: []})

      GenStage.sync_subscribe(aggregator, to: p1, cancel: :transient, index: 0)
      GenStage.sync_subscribe(aggregator, to: p2, cancel: :transient, index: 1)
      GenStage.sync_subscribe(aggregator, to: p3, cancel: :transient, index: 2)

      {:ok, consumer} = GenStage.start_link(TestEventConsumer, test_pid: self())
      GenStage.sync_subscribe(consumer, to: aggregator)

      # Send different amounts from each producer
      TestHelpers.send_events(p1, [%MarketEvent{data: %{"p1" => 1}}])

      TestHelpers.send_events(p2, [
        %MarketEvent{data: %{"p2" => 2}},
        %MarketEvent{data: %{"p2" => 3}}
      ])

      TestHelpers.send_events(p3, [%MarketEvent{data: %{"p3" => 4}}])

      # Should emit 1 event (min of 1, 2, 1)
      assert_receive {:events, events}, 1000
      assert length(events) == 1
      assert %MarketEvent{data: %{"p1" => 1, "p2" => 2, "p3" => 4}} = Enum.at(events, 0)
    end

    test "handles one producer being slower than others" do
      {:ok, aggregator} =
        AggregatorStage.start_link(
          producer_count: 2,
          max_demand: 10
        )

      {:ok, fast} = GenStage.start_link(ManualProducer, %{events: []})
      {:ok, slow} = GenStage.start_link(ManualProducer, %{events: []})

      GenStage.sync_subscribe(aggregator, to: fast, cancel: :transient, index: 0)
      GenStage.sync_subscribe(aggregator, to: slow, cancel: :transient, index: 1)

      {:ok, consumer} = GenStage.start_link(TestEventConsumer, test_pid: self())
      GenStage.sync_subscribe(consumer, to: aggregator)

      # Fast producer sends many events
      TestHelpers.send_events(fast, [
        %MarketEvent{data: %{"fast" => 1}},
        %MarketEvent{data: %{"fast" => 2}},
        %MarketEvent{data: %{"fast" => 3}},
        %MarketEvent{data: %{"fast" => 4}},
        %MarketEvent{data: %{"fast" => 5}}
      ])

      # Slow producer sends one
      TestHelpers.send_events(slow, [%MarketEvent{data: %{"slow" => :a}}])

      # Should emit only 1 event
      assert_receive {:events, events}, 1000
      assert length(events) == 1
      assert %MarketEvent{data: %{"fast" => 1, "slow" => :a}} = Enum.at(events, 0)

      # Slow sends another
      TestHelpers.send_events(slow, [%MarketEvent{data: %{"slow" => :b}}])

      # Should emit 1 more
      assert_receive {:events, events}, 1000
      assert length(events) == 1
      assert %MarketEvent{data: %{"fast" => 2, "slow" => :b}} = Enum.at(events, 0)
    end

    test "emits multiple synchronized events in batch" do
      {:ok, aggregator} =
        AggregatorStage.start_link(
          producer_count: 2,
          max_demand: 10
        )

      {:ok, p1} = GenStage.start_link(ManualProducer, %{events: []})
      {:ok, p2} = GenStage.start_link(ManualProducer, %{events: []})

      GenStage.sync_subscribe(aggregator, to: p1, cancel: :transient, index: 0)
      GenStage.sync_subscribe(aggregator, to: p2, cancel: :transient, index: 1)

      {:ok, consumer} = GenStage.start_link(TestEventConsumer, test_pid: self())
      GenStage.sync_subscribe(consumer, to: aggregator)

      # Both send same number of events
      TestHelpers.send_events(p1, [
        %MarketEvent{data: %{"p1" => 1}},
        %MarketEvent{data: %{"p1" => 2}},
        %MarketEvent{data: %{"p1" => 3}}
      ])

      TestHelpers.send_events(p2, [
        %MarketEvent{data: %{"p2" => :a}},
        %MarketEvent{data: %{"p2" => :b}},
        %MarketEvent{data: %{"p2" => :c}}
      ])

      # Should emit all 3 merged events
      assert_receive {:events, events}, 1000
      assert length(events) == 3
      assert %MarketEvent{data: %{"p1" => 1, "p2" => :a}} = Enum.at(events, 0)
      assert %MarketEvent{data: %{"p1" => 2, "p2" => :b}} = Enum.at(events, 1)
      assert %MarketEvent{data: %{"p1" => 3, "p2" => :c}} = Enum.at(events, 2)
    end

    test "handles producer cancellation with :transient" do
      {:ok, aggregator} =
        AggregatorStage.start_link(
          producer_count: 2,
          max_demand: 10
        )

      {:ok, p1} = GenStage.start_link(ManualProducer, %{events: []})
      {:ok, p2} = GenStage.start_link(ManualProducer, %{events: []})

      GenStage.sync_subscribe(aggregator, to: p1, cancel: :transient, index: 0)
      GenStage.sync_subscribe(aggregator, to: p2, cancel: :transient, index: 1)

      {:ok, consumer} = GenStage.start_link(TestEventConsumer, test_pid: self())
      GenStage.sync_subscribe(consumer, to: aggregator)

      # Send some events
      TestHelpers.send_events(p1, [%MarketEvent{data: %{"p1" => 1}}])
      TestHelpers.send_events(p2, [%MarketEvent{data: %{"p2" => :a}}])

      assert_receive {:events, _events}, 1000

      # Stop one producer
      GenStage.stop(p1)

      # Aggregator should still be alive
      Process.sleep(100)
      assert Process.alive?(aggregator)
    end

    test "preserves time and source from first event when merging" do
      {:ok, aggregator} =
        AggregatorStage.start_link(
          producer_count: 2,
          max_demand: 10
        )

      {:ok, p1} = GenStage.start_link(ManualProducer, %{events: []})
      {:ok, p2} = GenStage.start_link(ManualProducer, %{events: []})

      GenStage.sync_subscribe(aggregator, to: p1, cancel: :transient, index: 0)
      GenStage.sync_subscribe(aggregator, to: p2, cancel: :transient, index: 1)

      {:ok, consumer} = GenStage.start_link(TestEventConsumer, test_pid: self())
      GenStage.sync_subscribe(consumer, to: aggregator)

      time1 = ~U[2024-01-15 10:00:00Z]
      time2 = ~U[2024-01-15 10:00:01Z]

      # Send events with different times and sources
      TestHelpers.send_events(p1, [
        %MarketEvent{time: time1, source: "source1", data: %{"p1" => 1}},
        %MarketEvent{time: time2, source: "source1", data: %{"p1" => 2}}
      ])

      TestHelpers.send_events(p2, [
        %MarketEvent{time: time1, source: "source2", data: %{"p2" => :a}},
        %MarketEvent{time: time2, source: "source2", data: %{"p2" => :b}}
      ])

      # Receive merged events
      assert_receive {:events, events}, 1000
      assert length(events) == 2

      # First merged event should preserve time and source from first producer
      first_event = Enum.at(events, 0)

      assert %MarketEvent{time: ^time1, source: "source1", data: %{"p1" => 1, "p2" => :a}} =
               first_event

      # Second merged event
      second_event = Enum.at(events, 1)

      assert %MarketEvent{time: ^time2, source: "source1", data: %{"p1" => 2, "p2" => :b}} =
               second_event
    end
  end
end
