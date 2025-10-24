defmodule TheoryCraft.IndicatorValueTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.{Bar, IndicatorValue, Tick}

  ## Tests

  doctest TheoryCraft.IndicatorValue

  describe "bar_time/3" do
    test "extracts time from Bar" do
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

      indicator_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      event_data = %{"eurusd_m5" => bar}

      assert IndicatorValue.bar_time(indicator_value, event_data) == ~U[2024-01-01 10:00:00Z]
    end

    test "extracts time from Tick" do
      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        ask: 1.23,
        bid: 1.22,
        ask_volume: 100.0,
        bid_volume: 100.0
      }

      indicator_value = %IndicatorValue{value: 1.23, data_name: "eurusd_ticks"}
      event_data = %{"eurusd_ticks" => tick}

      assert IndicatorValue.bar_time(indicator_value, event_data) == ~U[2024-01-01 10:00:00Z]
    end

    test "follows IndicatorValue chain to find source time" do
      bar = %Bar{time: ~U[2024-01-01 10:00:00Z], close: 100.0}
      sma_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      ema_on_sma = %IndicatorValue{value: 45.1, data_name: "sma20"}

      event_data = %{
        "eurusd_m5" => bar,
        "sma20" => sma_value
      }

      assert IndicatorValue.bar_time(ema_on_sma, event_data) == ~U[2024-01-01 10:00:00Z]
    end

    test "returns default when source is not found" do
      indicator_value = %IndicatorValue{value: 45.0, data_name: "missing"}
      event_data = %{}
      default = ~U[2024-01-01 00:00:00Z]

      assert IndicatorValue.bar_time(indicator_value, event_data, default) == default
    end

    test "returns nil when source is not found and no default provided" do
      indicator_value = %IndicatorValue{value: 45.0, data_name: "missing"}
      event_data = %{}

      assert IndicatorValue.bar_time(indicator_value, event_data) == nil
    end
  end

  describe "new_bar?/2" do
    test "extracts new_bar? from Bar" do
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

      indicator_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      event_data = %{"eurusd_m5" => bar}

      assert IndicatorValue.new_bar?(indicator_value, event_data) == true
    end

    test "returns true for Tick (each tick is a new bar)" do
      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        ask: 1.23,
        bid: 1.22,
        ask_volume: 100.0,
        bid_volume: 100.0
      }

      indicator_value = %IndicatorValue{value: 1.23, data_name: "eurusd_ticks"}
      event_data = %{"eurusd_ticks" => tick}

      assert IndicatorValue.new_bar?(indicator_value, event_data) == true
    end

    test "follows IndicatorValue chain to find source Bar" do
      bar = %Bar{time: ~U[2024-01-01 10:00:00Z], close: 100.0, new_bar?: false}
      sma_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      ema_on_sma = %IndicatorValue{value: 45.1, data_name: "sma20"}

      event_data = %{
        "eurusd_m5" => bar,
        "sma20" => sma_value
      }

      assert IndicatorValue.new_bar?(ema_on_sma, event_data) == false
    end

    test "follows IndicatorValue chain to find source Tick" do
      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        ask: 1.23,
        bid: 1.22,
        ask_volume: 100.0,
        bid_volume: 100.0
      }

      tick_indicator = %IndicatorValue{value: 1.225, data_name: "eurusd_ticks"}
      nested_indicator = %IndicatorValue{value: 1.23, data_name: "tick_avg"}

      event_data = %{
        "eurusd_ticks" => tick,
        "tick_avg" => tick_indicator
      }

      assert IndicatorValue.new_bar?(nested_indicator, event_data) == true
    end

    test "raises when source is not found" do
      indicator_value = %IndicatorValue{value: 45.0, data_name: "missing"}
      event_data = %{}

      assert_raise RuntimeError,
                   ~r/IndicatorValue source "missing" not found in event data/,
                   fn ->
                     IndicatorValue.new_bar?(indicator_value, event_data)
                   end
    end

    test "raises when source is not Bar, Tick, or IndicatorValue" do
      indicator_value = %IndicatorValue{value: 45.0, data_name: "raw_value"}
      event_data = %{"raw_value" => 42.0}

      assert_raise RuntimeError,
                   ~r/IndicatorValue source "raw_value" is not a Bar, Tick, or IndicatorValue/,
                   fn ->
                     IndicatorValue.new_bar?(indicator_value, event_data)
                   end
    end
  end

  describe "new_market?/3" do
    test "extracts new_market? from Bar" do
      bar = %Bar{
        time: ~U[2024-01-01 10:00:00Z],
        open: 100.0,
        high: 102.0,
        low: 99.0,
        close: 101.0,
        volume: 1000.0,
        new_bar?: true,
        new_market?: true
      }

      indicator_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      event_data = %{"eurusd_m5" => bar}

      assert IndicatorValue.new_market?(indicator_value, event_data) == true
    end

    test "returns false for Tick (ticks don't have market boundaries)" do
      tick = %Tick{
        time: ~U[2024-01-01 10:00:00Z],
        ask: 1.23,
        bid: 1.22,
        ask_volume: 100.0,
        bid_volume: 100.0
      }

      indicator_value = %IndicatorValue{value: 1.23, data_name: "eurusd_ticks"}
      event_data = %{"eurusd_ticks" => tick}

      assert IndicatorValue.new_market?(indicator_value, event_data) == false
    end

    test "follows IndicatorValue chain to find source Bar" do
      bar = %Bar{time: ~U[2024-01-01 10:00:00Z], close: 100.0, new_market?: false}
      sma_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      ema_on_sma = %IndicatorValue{value: 45.1, data_name: "sma20"}

      event_data = %{
        "eurusd_m5" => bar,
        "sma20" => sma_value
      }

      assert IndicatorValue.new_market?(ema_on_sma, event_data) == false
    end

    test "raises when source is not found" do
      indicator_value = %IndicatorValue{value: 45.0, data_name: "missing"}
      event_data = %{}

      assert_raise RuntimeError,
                   ~r/IndicatorValue source "missing" not found in event data/,
                   fn ->
                     IndicatorValue.new_market?(indicator_value, event_data)
                   end
    end

    test "raises when source is not Bar, Tick, or IndicatorValue" do
      indicator_value = %IndicatorValue{value: 45.0, data_name: "raw_value"}
      event_data = %{"raw_value" => 42.0}

      assert_raise RuntimeError,
                   ~r/IndicatorValue source "raw_value" is not a Bar, Tick, or IndicatorValue/,
                   fn ->
                     IndicatorValue.new_market?(indicator_value, event_data)
                   end
    end
  end
end
