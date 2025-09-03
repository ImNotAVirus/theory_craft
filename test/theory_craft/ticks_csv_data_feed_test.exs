defmodule TheoryCraft.DataFeeds.TicksCSVDataFeedTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataFeeds.TicksCSVDataFeed
  alias TheoryCraft.Tick

  @fixture_path "test/fixtures/XAUUSD_ticks_dukascopy.csv"

  ## Tests

  describe "start_link/2" do
    test "successfully starts a GenStage producer with CSV file" do
      assert {:ok, pid} = TicksCSVDataFeed.start_link(@fixture_path, dukascopy_opts())
      assert is_pid(pid)
      GenStage.stop(pid)
    end

    @tag :capture_log
    test "fails when file does not exist" do
      {stream, pid} = ticks_feed_stream_and_pid("non_existent_file.csv")

      # The producer starts successfully but fails when consuming
      Process.flag(:trap_exit, true)
      _ = catch_exit(Enum.take(stream, 1))

      assert_received {:EXIT, ^pid, {error, _stacktrace}}
      assert %File.Error{reason: :enoent, path: "non_existent_file.csv"} = error
    end

    test "accepts GenServer options" do
      genserver_opts = [name: :test_csv_feed]
      opts = dukascopy_opts() ++ genserver_opts

      assert {:ok, pid} = TicksCSVDataFeed.start_link(@fixture_path, opts)
      assert Process.whereis(:test_csv_feed) == pid
      GenStage.stop(pid)
    end
  end

  describe "data streaming" do
    test "processes all rows from the CSV file" do
      stream = ticks_feed_stream(@fixture_path)
      ticks = Enum.to_list(stream)

      # Count lines in CSV file (excluding header)
      {:ok, content} = File.read(@fixture_path)
      lines = String.split(content, "\n", trim: true)
      # Exclude header
      expected_count = length(lines) - 1

      assert length(ticks) == expected_count
    end

    test "produces Tick structs from CSV data" do
      ticks =
        @fixture_path
        |> ticks_feed_stream()
        |> Enum.to_list()

      # Verify all items are Tick structs
      assert Enum.all?(ticks, &match?(%Tick{}, &1))
    end

    test "correctly parses time field with dukascopy format" do
      stream = ticks_feed_stream(@fixture_path)
      first_tick = Enum.at(stream, 0)

      # Note: The CSV shows "18.08.2025 00:00:01.154 GMT+0200" but after parsing it's in UTC
      # Adjusted to UTC from GMT+0200
      assert first_tick.time == ~U[2025-08-17 22:00:01.154000Z]
    end

    test "correctly parses numeric fields" do
      stream = ticks_feed_stream(@fixture_path)
      first_tick = Enum.at(stream, 0)

      # Based on first line of CSV: 3337.675,3336.015,450,450
      assert first_tick.ask == 3337.675
      assert first_tick.bid == 3336.015
      assert first_tick.ask_volume == 450.0
      assert first_tick.bid_volume == 450.0
    end
  end

  describe "error handling" do
    @tag :capture_log
    test "raises error when required header is missing" do
      invalid_options = Keyword.put(dukascopy_opts(), :time, "NonExistentTime")
      {stream, pid} = ticks_feed_stream_and_pid(@fixture_path, invalid_options)

      Process.flag(:trap_exit, true)
      _ = catch_exit(Enum.take(stream, 1))

      assert_received {:EXIT, ^pid, {error, _stacktrace}}
      assert %ArgumentError{message: "Header NonExistentTime not found"} = error
    end

    @tag :capture_log
    test "raises error with invalid header configuration" do
      # Invalid type
      invalid_options = Keyword.put(dukascopy_opts(), :time, %{invalid: "config"})
      {stream, pid} = ticks_feed_stream_and_pid(@fixture_path, invalid_options)

      Process.flag(:trap_exit, true)
      _ = catch_exit(Enum.take(stream, 1))

      assert_received {:EXIT, ^pid, {error, _stacktrace}}
      assert %ArgumentError{message: message} = error
      assert "Headers must be integers or binaries (got %{invalid: \"config\"})" = message
    end
  end

  describe "configuration options" do
    test "allows nil values for optional columns" do
      minimal_options = Keyword.merge(dukascopy_opts(), ask_volume: nil, bid_volume: nil)
      stream = ticks_feed_stream(@fixture_path, minimal_options)
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
      time: "Local time",
      ask: "Ask",
      bid: "Bid",
      ask_volume: "AskVolume",
      bid_volume: "BidVolume",
      skip_headers: false,
      time_format: :dukascopy
    ]
  end

  defp ticks_feed_stream(filename, opts \\ dukascopy_opts()) do
    {:ok, pid} = TicksCSVDataFeed.start_link(filename, opts)
    GenStage.stream([{pid, cancel: :transient}])
  end

  defp ticks_feed_stream_and_pid(filename, opts \\ dukascopy_opts()) do
    {:ok, pid} = TicksCSVDataFeed.start_link(filename, opts)
    {GenStage.stream([{pid, cancel: :transient}]), pid}
  end
end
