defmodule TheoryCraft.MarketSimulatorTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.MarketSimulator
  alias TheoryCraft.MarketEvent
  alias TheoryCraft.Tick
  alias TheoryCraft.Bar
  alias TheoryCraft.DataFeeds.MemoryDataFeed
  alias TheoryCraft.IndicatorValue
  alias TheoryCraft.TestIndicators.SimpleIndicator
  alias TheoryCraft.TestIndicators.SMAIndicator

  @moduletag :capture_log

  ## Setup

  setup_all do
    ticks = build_test_ticks()
    feed = MemoryDataFeed.new(ticks)

    on_exit(fn -> MemoryDataFeed.close(feed) end)

    {:ok, feed: feed, ticks: ticks}
  end

  ## Tests

  describe "MarketSimulator GenStage pipeline" do
    test "single resample layer", %{feed: feed} do
      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.stream()
        |> Enum.to_list()

      # Should have 5 events (one per tick, each with current bar state)
      assert length(events) == 5

      # All events should have bars
      for event <- events do
        assert %MarketEvent{data: %{"xauusd" => tick}} = event
        assert %MarketEvent{data: %{"xauusd_m5" => bar}} = event
        assert %Tick{} = tick
        assert %Bar{} = bar
      end

      # First 3 events should have bar at 00:00 (ticks at 00:00, 00:01, 00:02)
      for i <- 0..2 do
        assert %MarketEvent{data: %{"xauusd_m5" => bar}} = Enum.at(events, i)
        assert bar.time == ~U[2024-01-01 00:00:00.000000Z]
      end

      # Last 2 events should have bar at 00:05 (ticks at 00:05, 00:06)
      for i <- 3..4 do
        assert %MarketEvent{data: %{"xauusd_m5" => bar}} = Enum.at(events, i)
        assert bar.time == ~U[2024-01-01 00:05:00.000000Z]
      end
    end

    test "multiple sequential resample layers", %{feed: feed} do
      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m1", name: "xauusd_m1")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.stream()
        |> Enum.to_list()

      # Should have 5 events (one per tick flowing through the pipeline)
      assert length(events) == 5

      # All events should have tick and all bars
      for event <- events do
        assert %MarketEvent{data: %{"xauusd" => tick}} = event
        assert %MarketEvent{data: %{"xauusd_m1" => m1_bar}} = event
        assert %MarketEvent{data: %{"xauusd_m5" => m5_bar}} = event
        assert %Tick{} = tick
        assert %Bar{} = m1_bar
        assert %Bar{} = m5_bar
      end
    end

    test "parallel processors with add_indicators_layer", %{feed: feed} do
      # Test parallel processing with multiple indicators
      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", name: "indicator1", constant: 10.0},
          {SimpleIndicator, data: "xauusd_m5", name: "indicator2", constant: 20.0}
        ])
        |> MarketSimulator.stream()
        |> Enum.to_list()

      # Should emit events with merged data from both indicators
      assert length(events) == 5

      for event <- events do
        assert %MarketEvent{data: %{"xauusd" => tick}} = event
        assert %MarketEvent{data: %{"xauusd_m5" => m5_bar}} = event
        assert %MarketEvent{data: %{"indicator1" => ind1_value}} = event
        assert %MarketEvent{data: %{"indicator2" => ind2_value}} = event
        assert %Tick{} = tick
        assert %Bar{} = m5_bar
        assert %IndicatorValue{value: 10.0} = ind1_value
        assert %IndicatorValue{value: 20.0} = ind2_value
      end
    end

    test "mixed sequential and parallel layers", %{feed: feed} do
      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m1", name: "xauusd_m1")
        |> MarketSimulator.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m1", name: "ind1", constant: 5.0},
          {SMAIndicator, input: "xauusd_m1", name: "ind2", period: 3}
        ])
        |> MarketSimulator.resample("m5", name: "final")
        |> MarketSimulator.stream()
        |> Enum.to_list()

      # Should have 5 events (one per tick flowing through all layers)
      assert length(events) == 5

      for event <- events do
        assert %MarketEvent{data: %{"xauusd" => tick}} = event
        assert %MarketEvent{data: %{"xauusd_m1" => m1_bar}} = event
        assert %MarketEvent{data: %{"ind1" => ind1_value}} = event
        assert %MarketEvent{data: %{"ind2" => ind2_value}} = event
        assert %MarketEvent{data: %{"final" => final_bar}} = event
        assert %Tick{} = tick
        assert %Bar{} = m1_bar
        assert %IndicatorValue{value: 5.0} = ind1_value
        assert %IndicatorValue{value: value} = ind2_value
        assert is_number(value)
        assert %Bar{} = final_bar
      end
    end

    test "run/1 consumes entire stream", %{feed: feed} do
      result =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.run()

      assert result == :ok
    end

    test "add_indicator/3 creates single-processor layer", %{feed: feed} do
      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.add_indicator(SimpleIndicator,
          data: "xauusd_m5",
          name: "indicator",
          constant: 15.0
        )
        |> MarketSimulator.stream()
        |> Enum.to_list()

      # Should have 5 events (one per tick)
      assert length(events) == 5

      for event <- events do
        assert %MarketEvent{data: %{"xauusd" => tick}} = event
        assert %MarketEvent{data: %{"xauusd_m5" => m5_bar}} = event
        assert %MarketEvent{data: %{"indicator" => indicator_value}} = event
        assert %Tick{} = tick
        assert %Bar{} = m5_bar
        assert %IndicatorValue{value: 15.0} = indicator_value
      end
    end

    test "add_strategy supports multiple strategies with options", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.add_strategy(MyStrategy, risk_level: :high)
        |> MarketSimulator.add_strategy(AnotherStrategy, max_positions: 5, leverage: 2.0)

      assert length(simulator.strategies) == 2
      assert {MyStrategy, [risk_level: :high]} in simulator.strategies
      assert {AnotherStrategy, [max_positions: 5, leverage: 2.0]} in simulator.strategies
    end

    test "raises error when no data feed configured" do
      assert_raise ArgumentError, ~r/No data feed configured/, fn ->
        %MarketSimulator{}
        |> MarketSimulator.stream()
      end
    end

    test "raises error when adding second data feed" do
      assert_raise ArgumentError, ~r/only one data feed is supported/, fn ->
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, feed: :dummy1)
        |> MarketSimulator.add_data(MemoryDataFeed, feed: :dummy2)
      end
    end

    test "raises error for invalid timeframe" do
      assert_raise ArgumentError, ~r/Invalid timeframe "invalid_timeframe"/, fn ->
        %MarketSimulator{}
        |> MarketSimulator.resample("invalid_timeframe")
      end
    end

    test "raises error for empty indicator list in add_indicators_layer" do
      assert_raise ArgumentError, ~r/indicator_specs cannot be empty/, fn ->
        %MarketSimulator{}
        |> MarketSimulator.add_indicators_layer([])
      end
    end
  end

  describe "default names and data tracking" do
    test "add_data with module uses numeric index when name not provided", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed)

      # Default name should be 0 (first feed)
      assert simulator.data_streams == [0]
      assert [{0, {MemoryDataFeed, opts}}] = simulator.data_feeds
      # :name is NOT in opts (it's stored as the keyword list key)
      assert Keyword.fetch!(opts, :from) == feed
      refute Keyword.has_key?(opts, :name)
    end

    test "add_data with enumerable (list)", %{ticks: ticks} do
      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(ticks, name: "xauusd")
        |> MarketSimulator.resample("m5")
        |> MarketSimulator.stream()
        |> Enum.to_list()

      # Should have 5 events (one per tick)
      assert length(events) == 5

      # All events should have bars
      for event <- events do
        assert %MarketEvent{data: %{"xauusd" => tick}} = event
        assert %MarketEvent{data: %{"xauusd_m5" => bar}} = event
        assert %Tick{} = tick
        assert %Bar{} = bar
      end
    end

    test "add_data with enumerable (stream)", %{ticks: ticks} do
      stream = Stream.map(ticks, & &1)

      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(stream, name: "xauusd")
        |> MarketSimulator.resample("m5")
        |> MarketSimulator.stream()
        |> Enum.to_list()

      # Should have 5 events (one per tick)
      assert length(events) == 5

      # All events should have bars
      for event <- events do
        assert %MarketEvent{data: %{"xauusd" => tick}} = event
        assert %MarketEvent{data: %{"xauusd_m5" => bar}} = event
        assert %Tick{} = tick
        assert %Bar{} = bar
      end
    end

    test "resample uses data feed name by default", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        # No :data or :name
        |> MarketSimulator.resample("m5")

      # Should have generated data="XAUUSD" and name="XAUUSD_m5"
      assert "XAUUSD" in simulator.data_streams
      assert "XAUUSD_m5" in simulator.data_streams
    end

    test "resample generates output name as data_timeframe", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        |> MarketSimulator.resample("h1")

      assert "XAUUSD_h1" in simulator.data_streams
    end

    test "raises when data stream not found", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "ticks")

      assert_raise ArgumentError, ~r/Data stream "unknown" not found/, fn ->
        MarketSimulator.resample(simulator, "m5", data: "unknown")
      end
    end

    test "add_indicator validates data stream", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "ticks")

      assert_raise ArgumentError, ~r/Data stream "nonexistent" not found/, fn ->
        MarketSimulator.add_indicator(simulator, SimpleIndicator,
          constant: 10.0,
          name: "output",
          data: "nonexistent"
        )
      end
    end

    test "add_indicators_layer validates all data streams", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "ticks")
        |> MarketSimulator.resample("m5", name: "ticks_m5")

      assert_raise ArgumentError, ~r/Data stream "unknown" not found/, fn ->
        MarketSimulator.add_indicators_layer(simulator, [
          {SimpleIndicator, constant: 10.0, name: "out1", data: "ticks_m5"},
          {SimpleIndicator, constant: 20.0, name: "out2", data: "unknown"}
        ])
      end
    end

    test "data_feeds tracks only initial sources", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        |> MarketSimulator.resample("m5")
        |> MarketSimulator.resample("h1")

      # data_feeds should have only one feed
      assert length(simulator.data_feeds) == 1
    end

    test "data_streams tracks all data names", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        |> MarketSimulator.resample("m5")
        |> MarketSimulator.resample("h1")

      # data_streams should have feed + 2 resamples
      assert "XAUUSD" in simulator.data_streams
      assert "XAUUSD_m5" in simulator.data_streams
      assert "XAUUSD_h1" in simulator.data_streams
      assert length(simulator.data_streams) == 3
    end

    test "full pipeline without explicit data names works", %{feed: feed} do
      events =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        # data="XAUUSD", name="XAUUSD_m5" auto
        |> MarketSimulator.resample("m5")
        # data="XAUUSD", name="XAUUSD_h1" auto
        |> MarketSimulator.resample("h1")
        |> MarketSimulator.stream()
        |> Enum.take(5)

      # All events should have the data streams
      for event <- events do
        assert %MarketEvent{data: %{"XAUUSD" => tick}} = event
        assert %MarketEvent{data: %{"XAUUSD_m5" => m5_bar}} = event
        assert %MarketEvent{data: %{"XAUUSD_h1" => h1_bar}} = event
        assert %Tick{} = tick
        assert %Bar{} = m5_bar
        assert %Bar{} = h1_bar
      end
    end

    test "add_indicator generates name from module when not provided", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 10.0)

      # Should generate "simple_indicator" from module name
      assert "simple_indicator" in simulator.data_streams
    end

    test "add_indicator with multiple same modules adds numeric suffix", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 10.0)
        |> MarketSimulator.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 20.0)
        |> MarketSimulator.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 30.0)

      # Should generate: "simple_indicator", "simple_indicator_1", "simple_indicator_2"
      assert "simple_indicator" in simulator.data_streams
      assert "simple_indicator_1" in simulator.data_streams
      assert "simple_indicator_2" in simulator.data_streams
    end

    test "add_indicator raises when explicit name is already taken", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")

      assert_raise ArgumentError, ~r/Data stream name "xauusd_m5" is already taken/, fn ->
        MarketSimulator.add_indicator(simulator, SimpleIndicator,
          data: "xauusd_m5",
          name: "xauusd_m5",
          constant: 10.0
        )
      end
    end

    test "add_indicators_layer generates names from modules when not provided", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", constant: 10.0},
          {SMAIndicator, input: "xauusd_m5", period: 3}
        ])

      # Should generate "simple_indicator" and "sma_indicator"
      assert "simple_indicator" in simulator.data_streams
      assert "sma_indicator" in simulator.data_streams
    end

    test "add_indicators_layer handles multiple same modules in single layer", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", constant: 10.0},
          {SimpleIndicator, data: "xauusd_m5", constant: 20.0},
          {SimpleIndicator, data: "xauusd_m5", constant: 30.0}
        ])

      # Should generate: "simple_indicator", "simple_indicator_1", "simple_indicator_2"
      assert "simple_indicator" in simulator.data_streams
      assert "simple_indicator_1" in simulator.data_streams
      assert "simple_indicator_2" in simulator.data_streams
    end

    test "add_indicators_layer raises when explicit name is already taken", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")

      assert_raise ArgumentError, ~r/Data stream name "xauusd_m5" is already taken/, fn ->
        MarketSimulator.add_indicators_layer(simulator, [
          {SimpleIndicator, data: "xauusd_m5", name: "xauusd_m5", constant: 10.0}
        ])
      end
    end

    test "add_indicators_layer raises when duplicate name in same layer", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")

      assert_raise ArgumentError, ~r/Data stream name "duplicate" is already taken/, fn ->
        MarketSimulator.add_indicators_layer(simulator, [
          {SimpleIndicator, data: "xauusd_m5", name: "duplicate", constant: 10.0},
          {SMAIndicator, input: "xauusd_m5", name: "duplicate", period: 3}
        ])
      end
    end

    test "mixed explicit and generated names in add_indicators_layer", %{feed: feed} do
      simulator =
        %MarketSimulator{}
        |> MarketSimulator.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSimulator.resample("m5", name: "xauusd_m5")
        |> MarketSimulator.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", name: "explicit_name", constant: 10.0},
          {SimpleIndicator, data: "xauusd_m5", constant: 20.0},
          {SMAIndicator, input: "xauusd_m5", period: 3}
        ])

      # Should have "explicit_name", "simple_indicator" (auto), "sma_indicator" (auto)
      assert "explicit_name" in simulator.data_streams
      assert "simple_indicator" in simulator.data_streams
      assert "sma_indicator" in simulator.data_streams
    end
  end

  ## Private helper functions

  defp build_test_ticks() do
    [
      %Tick{
        time: ~U[2024-01-01 00:00:00.000000Z],
        ask: 2500.0,
        bid: 2499.0,
        ask_volume: 100.0,
        bid_volume: 150.0
      },
      %Tick{
        time: ~U[2024-01-01 00:01:00.000000Z],
        ask: 2501.0,
        bid: 2500.0,
        ask_volume: 100.0,
        bid_volume: 150.0
      },
      %Tick{
        time: ~U[2024-01-01 00:02:00.000000Z],
        ask: 2502.0,
        bid: 2501.0,
        ask_volume: 100.0,
        bid_volume: 150.0
      },
      %Tick{
        time: ~U[2024-01-01 00:05:00.000000Z],
        ask: 2503.0,
        bid: 2502.0,
        ask_volume: 100.0,
        bid_volume: 150.0
      },
      %Tick{
        time: ~U[2024-01-01 00:06:00.000000Z],
        ask: 2504.0,
        bid: 2503.0,
        ask_volume: 100.0,
        bid_volume: 150.0
      }
    ]
  end
end
