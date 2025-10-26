defmodule TheoryCraft.MarketSource.MarketEventTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.MarketSource.{Bar, Tick}
  alias TheoryCraft.MarketSource.{IndicatorValue, MarketEvent}

  ## Tests

  doctest TheoryCraft.MarketSource.MarketEvent

  describe "extract_value/3" do
    test "extracts close from Bar with MarketEvent" do
      event = build_event()
      assert MarketEvent.extract_value(event, "eurusd_m5", :close) == 101.0
    end

    test "extracts high from Bar with MarketEvent" do
      event = build_event()
      assert MarketEvent.extract_value(event, "eurusd_m5", :high) == 102.0
    end

    test "extracts value from IndicatorValue with MarketEvent" do
      event = build_event()
      assert MarketEvent.extract_value(event, "sma20", nil) == 45.0
    end

    test "extracts raw value with MarketEvent" do
      event = build_event()
      assert MarketEvent.extract_value(event, "raw_value", nil) == 42.0
    end

    test "raises when data_name not found with MarketEvent" do
      event = %MarketEvent{data: %{}}

      assert_raise RuntimeError, ~r/data_name "missing" not found in event/, fn ->
        MarketEvent.extract_value(event, "missing", :close)
      end
    end

    test "raises when source not found in Bar with MarketEvent" do
      event = build_event()

      assert_raise RuntimeError, ~r/source :missing not found in data/, fn ->
        MarketEvent.extract_value(event, "eurusd_m5", :missing)
      end
    end
  end

  describe "extract_time/2" do
    test "extracts time from Bar" do
      event = build_event()
      assert MarketEvent.extract_time(event, "eurusd_m5") == ~U[2024-01-01 10:00:00Z]
    end

    test "extracts time from Tick" do
      tick = %Tick{
        time: ~U[2024-01-01 10:02:34Z],
        ask: 1.23,
        bid: 1.22,
        ask_volume: 100.0,
        bid_volume: 100.0
      }

      event = %MarketEvent{data: %{"eurusd_ticks" => tick}}
      assert MarketEvent.extract_time(event, "eurusd_ticks") == ~U[2024-01-01 10:02:34Z]
    end

    test "extracts time from IndicatorValue (lazy lookup)" do
      event = build_event()
      assert MarketEvent.extract_time(event, "sma20") == ~U[2024-01-01 10:00:00Z]
    end

    test "handles nested IndicatorValue" do
      nested_indicator = %IndicatorValue{value: 46.0, data_name: "sma20"}
      bar = %Bar{time: ~U[2024-01-01 11:00:00Z], close: 100.0}
      sma_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}

      event = %MarketEvent{
        time: ~U[2024-01-01 11:02:34Z],
        source: "eurusd_m5",
        data: %{
          "eurusd_m5" => bar,
          "sma20" => sma_value,
          "ema_on_sma" => nested_indicator
        }
      }

      assert MarketEvent.extract_time(event, "ema_on_sma") == ~U[2024-01-01 11:00:00Z]
    end

    test "raises when data_name not found" do
      event = %MarketEvent{data: %{}}

      assert_raise RuntimeError, ~r/data_name "missing" not found in event/, fn ->
        MarketEvent.extract_time(event, "missing")
      end
    end

    test "raises when data doesn't have a time field" do
      event = %MarketEvent{data: %{"raw_value" => 42.0}}

      assert_raise RuntimeError, ~r/data "raw_value" doesn't have a time field/, fn ->
        MarketEvent.extract_time(event, "raw_value")
      end
    end
  end

  describe "new_bar?/2" do
    test "extracts new_bar? from Bar with MarketEvent" do
      event = build_event()
      assert MarketEvent.new_bar?(event, "eurusd_m5") == true
    end

    test "returns true for Tick (each tick is a new bar)" do
      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        ask: 1.23,
        bid: 1.22,
        ask_volume: 100.0,
        bid_volume: 100.0
      }

      event = %MarketEvent{data: %{"eurusd_ticks" => tick}}
      assert MarketEvent.new_bar?(event, "eurusd_ticks") == true
    end

    test "returns true for IndicatorValue with MarketEvent (lazy lookup)" do
      event = build_event()
      assert MarketEvent.new_bar?(event, "sma20") == true
    end

    test "handles nested IndicatorValue with MarketEvent" do
      nested_indicator = %IndicatorValue{value: 46.0, data_name: "sma20"}
      bar = %Bar{time: ~U[2024-01-01 10:00:00Z], close: 100.0, new_bar?: false}
      sma_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}

      event = %MarketEvent{
        time: ~U[2024-01-01 10:00:00Z],
        source: "eurusd_m5",
        data: %{
          "eurusd_m5" => bar,
          "sma20" => sma_value,
          "ema_on_sma" => nested_indicator
        }
      }

      assert MarketEvent.new_bar?(event, "ema_on_sma") == false
    end

    test "raises when data_name not found with MarketEvent" do
      event = %MarketEvent{data: %{}}

      assert_raise RuntimeError, ~r/data_name "missing" not found in event/, fn ->
        MarketEvent.new_bar?(event, "missing")
      end
    end

    test "raises when data is not Bar, Tick, or IndicatorValue" do
      event = %MarketEvent{data: %{"raw_value" => 42.0}}

      assert_raise RuntimeError, ~r/data "raw_value" is not a Bar, Tick, or IndicatorValue/, fn ->
        MarketEvent.new_bar?(event, "raw_value")
      end
    end
  end

  describe "new_market?/2" do
    test "extracts new_market? from Bar with MarketEvent" do
      event = build_event()
      assert MarketEvent.new_market?(event, "eurusd_m5") == false
    end

    test "returns false for Tick (ticks don't have market boundaries)" do
      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        ask: 1.23,
        bid: 1.22,
        ask_volume: 100.0,
        bid_volume: 100.0
      }

      event = %MarketEvent{data: %{"eurusd_ticks" => tick}}
      assert MarketEvent.new_market?(event, "eurusd_ticks") == false
    end

    test "returns false for IndicatorValue with MarketEvent (lazy lookup)" do
      event = build_event()
      assert MarketEvent.new_market?(event, "sma20") == false
    end

    test "handles nested IndicatorValue with MarketEvent" do
      nested_indicator = %IndicatorValue{value: 46.0, data_name: "sma20"}
      bar = %Bar{time: ~U[2024-01-01 10:00:00Z], close: 100.0, new_market?: true}
      sma_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}

      event = %MarketEvent{
        time: ~U[2024-01-01 10:00:00Z],
        source: "eurusd_m5",
        data: %{
          "eurusd_m5" => bar,
          "sma20" => sma_value,
          "ema_on_sma" => nested_indicator
        }
      }

      assert MarketEvent.new_market?(event, "ema_on_sma") == true
    end

    test "raises when data_name not found with MarketEvent" do
      event = %MarketEvent{data: %{}}

      assert_raise RuntimeError, ~r/data_name "missing" not found in event/, fn ->
        MarketEvent.new_market?(event, "missing")
      end
    end

    test "raises when data is not Bar, Tick, or IndicatorValue" do
      event = %MarketEvent{data: %{"raw_value" => 42.0}}

      assert_raise RuntimeError, ~r/data "raw_value" is not a Bar, Tick, or IndicatorValue/, fn ->
        MarketEvent.new_market?(event, "raw_value")
      end
    end
  end

  ## Private helper functions

  defp build_event do
    bar = %Bar{
      time: ~U[2024-01-01 10:00:00Z],
      open: 100.0,
      high: 102.0,
      low: 99.0,
      close: 101.0,
      volume: 1000.0,
      new_bar?: true,
      new_market?: false
    }

    indicator_value = %IndicatorValue{
      value: 45.0,
      data_name: "eurusd_m5"
    }

    event_data = %{
      "eurusd_m5" => bar,
      "sma20" => indicator_value,
      "raw_value" => 42.0
    }

    %MarketEvent{
      time: ~U[2024-01-01 10:00:00Z],
      source: "eurusd_m5",
      data: event_data
    }
  end
end
