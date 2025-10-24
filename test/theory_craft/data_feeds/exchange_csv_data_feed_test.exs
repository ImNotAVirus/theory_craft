defmodule TheoryCraft.DataFeeds.ExchangeCSVDataFeedTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataFeeds.ExchangeCSVDataFeed
  alias TheoryCraft.ExchangeData

  @fixture_path "test/fixtures/exchange_metrics_sample.csv"

  ## Tests

  describe "stream/1" do
    test "successfully creates a stream with CSV file" do
      assert {:ok, stream} = ExchangeCSVDataFeed.stream(base_opts())
      assert Enumerable.impl_for(stream)
    end

    test "requires file option" do
      opts = base_opts() |> Keyword.delete(:file)
      assert {:error, ":file option is required"} = ExchangeCSVDataFeed.stream(opts)
    end
  end

  describe "data streaming" do
    test "parses exchange metrics with header mapping" do
      {:ok, stream} = ExchangeCSVDataFeed.stream(base_opts())
      [first | _] = Enum.to_list(stream)

      assert %ExchangeData{} = first
      assert first.symbol == "BTCUSDT"
      assert first.price == 42_000.5
      assert first.open_interest == 123_456.789
      assert first.volume == 987.654
      assert first.funding_rate == 0.0001
      assert first.time == ~U[2024-01-01 00:00:00Z]
    end

    test "supports parsing with column indexes when headers are skipped" do
      opts =
        base_opts()
        |> Keyword.merge(
          skip_headers: true,
          time: 0,
          symbol: 1,
          price: 2,
          open_interest: 3,
          volume: 4,
          funding_rate: 5
        )

      {:ok, stream} = ExchangeCSVDataFeed.stream(opts)
      data = Enum.to_list(stream)

      assert length(data) == 2
      last = List.last(data)

      assert %ExchangeData{} = last
      assert last.symbol == "ETHUSDT"
      assert last.price == 3_200.25
      assert last.funding_rate == nil
    end
  end

  describe "error handling" do
    test "raises when configured header is missing" do
      opts = Keyword.put(base_opts(), :open_interest, "missing_header")
      {:ok, stream} = ExchangeCSVDataFeed.stream(opts)

      assert_raise ArgumentError, "Header missing_header not found", fn ->
        Enum.take(stream, 1)
      end
    end
  end

  ## Helpers

  defp base_opts() do
    [
      file: @fixture_path,
      time: "timestamp",
      symbol: "symbol",
      price: "price",
      open_interest: "open_interest",
      volume: "volume",
      funding_rate: "funding_rate",
      skip_headers: false,
      nil_value: "",
      time_format: &iso8601!/1
    ]
  end

  defp iso8601!(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end
end

