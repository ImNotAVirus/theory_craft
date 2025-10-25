defmodule TheoryCraft.MarketSourceTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.MarketSource
  alias TheoryCraft.MarketSource.MarketEvent
  alias TheoryCraft.MarketSource.Tick
  alias TheoryCraft.MarketSource.Bar
  alias TheoryCraft.MarketSource.MemoryDataFeed
  alias TheoryCraft.MarketSource.IndicatorValue
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

  describe "MarketSource GenStage pipeline" do
    test "single resample layer", %{feed: feed} do
      events =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.stream()
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
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m1", name: "xauusd_m1")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.stream()
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
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", name: "indicator1", constant: 10.0},
          {SimpleIndicator, data: "xauusd_m5", name: "indicator2", constant: 20.0}
        ])
        |> MarketSource.stream()
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
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m1", name: "xauusd_m1")
        |> MarketSource.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m1", name: "ind1", constant: 5.0},
          {SMAIndicator, input: "xauusd_m1", name: "ind2", period: 3}
        ])
        |> MarketSource.resample("m5", name: "final")
        |> MarketSource.stream()
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

    test "add_indicator/3 creates single-processor layer", %{feed: feed} do
      events =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.add_indicator(SimpleIndicator,
          data: "xauusd_m5",
          name: "indicator",
          constant: 15.0
        )
        |> MarketSource.stream()
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
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.add_strategy(MyStrategy, risk_level: :high)
        |> MarketSource.add_strategy(AnotherStrategy, max_positions: 5, leverage: 2.0)

      assert length(market.strategies) == 2
      assert {MyStrategy, [risk_level: :high]} in market.strategies
      assert {AnotherStrategy, [max_positions: 5, leverage: 2.0]} in market.strategies
    end

    test "raises error when no data feed configured" do
      assert_raise ArgumentError, ~r/No data feed configured/, fn ->
        %MarketSource{}
        |> MarketSource.stream()
      end
    end

    test "raises error when adding second data feed" do
      assert_raise ArgumentError, ~r/only one data feed is supported/, fn ->
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, feed: :dummy1)
        |> MarketSource.add_data(MemoryDataFeed, feed: :dummy2)
      end
    end

    test "raises error for invalid timeframe" do
      assert_raise ArgumentError, ~r/Invalid timeframe "invalid_timeframe"/, fn ->
        %MarketSource{}
        |> MarketSource.resample("invalid_timeframe")
      end
    end

    test "raises error for empty indicator list in add_indicators_layer" do
      assert_raise ArgumentError, ~r/indicator_specs cannot be empty/, fn ->
        %MarketSource{}
        |> MarketSource.add_indicators_layer([])
      end
    end
  end

  describe "default names and data tracking" do
    test "add_data with module uses numeric index when name not provided", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed)

      # Default name should be 0 (first feed)
      assert market.data_streams == [0]
      assert [{0, {MemoryDataFeed, opts}}] = market.data_feeds
      # :name is NOT in opts (it's stored as the keyword list key)
      assert Keyword.fetch!(opts, :from) == feed
      refute Keyword.has_key?(opts, :name)
    end

    test "add_data with enumerable (list)", %{ticks: ticks} do
      events =
        %MarketSource{}
        |> MarketSource.add_data(ticks, name: "xauusd")
        |> MarketSource.resample("m5")
        |> MarketSource.stream()
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
        %MarketSource{}
        |> MarketSource.add_data(stream, name: "xauusd")
        |> MarketSource.resample("m5")
        |> MarketSource.stream()
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
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        # No :data or :name
        |> MarketSource.resample("m5")

      # Should have generated data="XAUUSD" and name="XAUUSD_m5"
      assert "XAUUSD" in market.data_streams
      assert "XAUUSD_m5" in market.data_streams
    end

    test "resample generates output name as data_timeframe", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        |> MarketSource.resample("h1")

      assert "XAUUSD_h1" in market.data_streams
    end

    test "raises when data stream not found", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "ticks")

      assert_raise ArgumentError, ~r/Data stream "unknown" not found/, fn ->
        MarketSource.resample(market, "m5", data: "unknown")
      end
    end

    test "add_indicator validates data stream", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "ticks")

      assert_raise ArgumentError, ~r/Data stream "nonexistent" not found/, fn ->
        MarketSource.add_indicator(market, SimpleIndicator,
          constant: 10.0,
          name: "output",
          data: "nonexistent"
        )
      end
    end

    test "add_indicators_layer validates all data streams", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "ticks")
        |> MarketSource.resample("m5", name: "ticks_m5")

      assert_raise ArgumentError, ~r/Data stream "unknown" not found/, fn ->
        MarketSource.add_indicators_layer(market, [
          {SimpleIndicator, data: "ticks_m5", constant: 10.0, name: "out1"},
          {SimpleIndicator, data: "unknown", constant: 20.0, name: "out2"}
        ])
      end
    end

    test "data_feeds tracks only initial sources", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        |> MarketSource.resample("m5")
        |> MarketSource.resample("h1")

      # data_feeds should have only one feed
      assert length(market.data_feeds) == 1
    end

    test "data_streams tracks all data names", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        |> MarketSource.resample("m5")
        |> MarketSource.resample("h1")

      # data_streams should have feed + 2 resamples
      assert "XAUUSD" in market.data_streams
      assert "XAUUSD_m5" in market.data_streams
      assert "XAUUSD_h1" in market.data_streams
      assert length(market.data_streams) == 3
    end

    test "full pipeline without explicit data names works", %{feed: feed} do
      events =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
        # data="XAUUSD", name="XAUUSD_m5" auto
        |> MarketSource.resample("m5")
        # data="XAUUSD", name="XAUUSD_h1" auto
        |> MarketSource.resample("h1")
        |> MarketSource.stream()
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
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 10.0)

      # Should generate "simple_indicator" from module name
      assert "simple_indicator" in market.data_streams
    end

    test "add_indicator with multiple same modules adds numeric suffix", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 10.0)
        |> MarketSource.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 20.0)
        |> MarketSource.add_indicator(SimpleIndicator, data: "xauusd_m5", constant: 30.0)

      # Should generate: "simple_indicator", "simple_indicator_1", "simple_indicator_2"
      assert "simple_indicator" in market.data_streams
      assert "simple_indicator_1" in market.data_streams
      assert "simple_indicator_2" in market.data_streams
    end

    test "add_indicator raises when explicit name is already taken", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")

      assert_raise ArgumentError, ~r/Data stream name "xauusd_m5" is already taken/, fn ->
        MarketSource.add_indicator(market, SimpleIndicator,
          data: "xauusd_m5",
          name: "xauusd_m5",
          constant: 10.0
        )
      end
    end

    test "add_indicators_layer generates names from modules when not provided", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", constant: 10.0},
          {SMAIndicator, input: "xauusd_m5", period: 3}
        ])

      # Should generate "simple_indicator" and "sma_indicator"
      assert "simple_indicator" in market.data_streams
      assert "sma_indicator" in market.data_streams
    end

    test "add_indicators_layer handles multiple same modules in single layer", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", constant: 10.0},
          {SimpleIndicator, data: "xauusd_m5", constant: 20.0},
          {SimpleIndicator, data: "xauusd_m5", constant: 30.0}
        ])

      # Should generate: "simple_indicator", "simple_indicator_1", "simple_indicator_2"
      assert "simple_indicator" in market.data_streams
      assert "simple_indicator_1" in market.data_streams
      assert "simple_indicator_2" in market.data_streams
    end

    test "add_indicators_layer raises when explicit name is already taken", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")

      assert_raise ArgumentError, ~r/Data stream name "xauusd_m5" is already taken/, fn ->
        MarketSource.add_indicators_layer(market, [
          {SimpleIndicator, data: "xauusd_m5", name: "xauusd_m5", constant: 10.0}
        ])
      end
    end

    test "add_indicators_layer raises when duplicate name in same layer", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")

      assert_raise ArgumentError, ~r/Data stream name "duplicate" is already taken/, fn ->
        MarketSource.add_indicators_layer(market, [
          {SimpleIndicator, data: "xauusd_m5", name: "duplicate", constant: 10.0},
          {SMAIndicator, input: "xauusd_m5", name: "duplicate", period: 3}
        ])
      end
    end

    test "mixed explicit and generated names in add_indicators_layer", %{feed: feed} do
      market =
        %MarketSource{}
        |> MarketSource.add_data(MemoryDataFeed, from: feed, name: "xauusd")
        |> MarketSource.resample("m5", name: "xauusd_m5")
        |> MarketSource.add_indicators_layer([
          {SimpleIndicator, data: "xauusd_m5", name: "explicit_name", constant: 10.0},
          {SimpleIndicator, data: "xauusd_m5", constant: 20.0},
          {SMAIndicator, input: "xauusd_m5", period: 3}
        ])

      # Should have "explicit_name", "simple_indicator" (auto), "sma_indicator" (auto)
      assert "explicit_name" in market.data_streams
      assert "simple_indicator" in market.data_streams
      assert "sma_indicator" in market.data_streams
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
