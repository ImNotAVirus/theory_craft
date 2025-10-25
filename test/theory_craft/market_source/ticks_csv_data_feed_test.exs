defmodule TheoryCraft.MarketSource.TicksCSVDataFeedTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.MarketSource.{Tick, TicksCSVDataFeed}

  @fixture_path "test/fixtures/XAUUSD_ticks_dukascopy.csv"

  ## Tests

  describe "stream/1" do
    test "successfully creates a stream with CSV file" do
      assert {:ok, stream} = TicksCSVDataFeed.stream(dukascopy_opts())
      assert Enumerable.impl_for(stream)
    end

    test "fails when file does not exist" do
      opts = Keyword.put(dukascopy_opts(), :file, "non_existent_file.csv")
      {:ok, stream} = TicksCSVDataFeed.stream(opts)

      assert_raise File.Error, ~r/no such file or directory/, fn ->
        Enum.take(stream, 1)
      end
    end

    test "requires file option" do
      opts = Keyword.delete(dukascopy_opts(), :file)
      assert {:error, ":file option is required"} = TicksCSVDataFeed.stream(opts)
    end
  end

  describe "stream!/1" do
    test "returns stream directly on success" do
      stream = TicksCSVDataFeed.stream!(dukascopy_opts())
      assert Enumerable.impl_for(stream)

      # Should be able to consume it
      first_tick = Enum.at(stream, 0)
      assert %Tick{} = first_tick
    end

    test "raises on error" do
      opts = Keyword.delete(dukascopy_opts(), :file)

      assert_raise ArgumentError, ~r/Failed to create stream/, fn ->
        TicksCSVDataFeed.stream!(opts)
      end
    end
  end

  describe "data streaming" do
    test "processes all rows from the CSV file" do
      {:ok, stream} = TicksCSVDataFeed.stream(dukascopy_opts())
      ticks = Enum.to_list(stream)

      # Count lines in CSV file (excluding header)
      {:ok, content} = File.read(@fixture_path)
      lines = String.split(content, "\n", trim: true)
      # Exclude header
      expected_count = length(lines) - 1

      assert length(ticks) == expected_count
    end

    test "produces Tick events from CSV data" do
      {:ok, stream} = TicksCSVDataFeed.stream(dukascopy_opts())
      assert Enum.all?(stream, &match?(%Tick{}, &1))
    end

    test "correctly parses time field with dukascopy format" do
      {:ok, stream} = TicksCSVDataFeed.stream(dukascopy_opts())
      first_tick = Enum.at(stream, 0)

      # Note: The CSV shows "18.08.2025 00:00:01.154 GMT+0200" but after parsing it's in UTC
      # Adjusted to UTC from GMT+0200
      assert first_tick.time == ~U[2025-08-17 22:00:01.154000Z]
    end

    test "correctly parses numeric fields" do
      {:ok, stream} = TicksCSVDataFeed.stream(dukascopy_opts())
      first_tick = Enum.at(stream, 0)

      # Based on first line of CSV: 3337.675,3336.015,450,450
      assert first_tick.ask == 3337.675
      assert first_tick.bid == 3336.015
      assert first_tick.ask_volume == 450.0
      assert first_tick.bid_volume == 450.0
    end
  end

  describe "error handling" do
    test "raises error when required header is missing" do
      invalid_options = Keyword.put(dukascopy_opts(), :time, "NonExistentTime")
      {:ok, stream} = TicksCSVDataFeed.stream(invalid_options)

      assert_raise ArgumentError, "Header NonExistentTime not found", fn ->
        Enum.take(stream, 1)
      end
    end

    test "raises error with invalid header configuration" do
      invalid_options = Keyword.put(dukascopy_opts(), :time, %{invalid: "config"})
      {:ok, stream} = TicksCSVDataFeed.stream(invalid_options)

      assert_raise ArgumentError, ~r/Headers must be integers or binaries/, fn ->
        Enum.take(stream, 1)
      end
    end
  end

  describe "configuration options" do
    test "allows nil values for optional columns" do
      minimal_options = Keyword.merge(dukascopy_opts(), ask_volume: nil, bid_volume: nil)

      {:ok, stream} = TicksCSVDataFeed.stream(minimal_options)
      first_tick = Enum.at(stream, 0)

      # Verify that nil columns are not set
      assert is_nil(first_tick.ask_volume)
      assert is_nil(first_tick.bid_volume)

      # But other fields should be populated
      assert is_float(first_tick.ask)
      assert is_float(first_tick.bid)
      assert %DateTime{} = first_tick.time
    end
  end

  ## Private functions

  defp dukascopy_opts() do
    [
      file: @fixture_path,
      time: "Local time",
      ask: "Ask",
      bid: "Bid",
      ask_volume: "AskVolume",
      bid_volume: "BidVolume",
      skip_headers: false,
      time_format: :dukascopy
    ]
  end
end
