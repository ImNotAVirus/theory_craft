defmodule TheoryCraft.DataFeeds.BinanceProviderTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataFeeds.BinanceProvider
  alias TheoryCraft.ExchangeData

  @kline_one [
    1_700_000_000_000,
    "42000.5",
    "42050.0",
    "41900.0",
    "42010.0",
    "1500.0",
    1_700_000_059_999,
    "0",
    1_000,
    "750.0",
    "31500000.0",
    "0"
  ]

  @kline_two [
    1_700_000_060_000,
    "42010.0",
    "42100.0",
    "42000.0",
    "42080.0",
    "900.0",
    1_700_000_119_999,
    "0",
    850,
    "450.0",
    "18900000.0",
    "0"
  ]

  test "fetch_historical/1 converts klines to ExchangeData structures" do
    http_client =
      sequential_stub([
        fn request ->
          assert request.url == "https://api.binance.com/api/v3/klines"
          assert Keyword.get(request.params, :symbol) == "BTCUSDT"
          assert Keyword.get(request.params, :interval) == "1m"

          {:ok, [@kline_one, @kline_two]}
        end
      ])

    assert {:ok, [%ExchangeData{} = first, %ExchangeData{} = second]} =
             BinanceProvider.fetch_historical(
               symbol: "btcusdt",
               interval: :"1m",
               http_client: http_client
             )

    assert first.symbol == "BTCUSDT"
    assert_in_delta(first.price, 42_010.0, 1.0e-6)
    assert_in_delta(first.volume, 1_500.0, 1.0e-6)
    assert DateTime.to_unix(first.time, :millisecond) == Enum.at(@kline_one, 6)

    assert second.symbol == "BTCUSDT"
    assert DateTime.to_unix(second.time, :millisecond) == Enum.at(@kline_two, 6)
  end

  test "fetch_historical/1 surfaces missing options" do
    assert {:error, {:missing_option, :symbol}} =
             BinanceProvider.fetch_historical(interval: "1h")

    assert {:error, {:missing_option, :interval}} =
             BinanceProvider.fetch_historical(symbol: "BTCUSDT")
  end

  test "fetch_historical/1 returns transport errors" do
    http_client =
      sequential_stub([
        fn _request -> {:error, {:http_error, 500, "bang"}} end
      ])

    assert {:error, {:http_error, 500, "bang"}} =
             BinanceProvider.fetch_historical(
               symbol: "BTCUSDT",
               interval: "1m",
               http_client: http_client
             )
  end

  test "start_live/1 builds state and fetch_live/1 yields new klines only" do
    http_client =
      sequential_stub([
        fn _request -> {:ok, [@kline_one]} end,
        fn _request -> {:ok, [@kline_one, @kline_two]} end,
        fn _request -> {:ok, [@kline_two]} end
      ])

    assert {:ok, state} =
             BinanceProvider.start_live(
               symbol: "BTCUSDT",
               interval: "1m",
               http_client: http_client,
               live_limit: 2
             )

    assert {:ok, {events, state}} = BinanceProvider.fetch_live(state)
    assert [%ExchangeData{} = first] = events
    assert DateTime.to_unix(first.time, :millisecond) == Enum.at(@kline_one, 6)

    assert {:ok, {events, state}} = BinanceProvider.fetch_live(state)
    assert [%ExchangeData{} = second] = events
    assert DateTime.to_unix(second.time, :millisecond) == Enum.at(@kline_two, 6)

    # No new klines - returns empty list
    assert {:ok, {[], _state}} = BinanceProvider.fetch_live(state)
  end

  test "fetch_live/1 propagates transport errors" do
    http_client =
      sequential_stub([
        fn _request -> {:error, :timeout} end
      ])

    {:ok, state} =
      BinanceProvider.start_live(
        symbol: "BTCUSDT",
        interval: "1m",
        http_client: http_client
      )

    assert {:error, :timeout} = BinanceProvider.fetch_live(state)
  end

  defp sequential_stub(responses) when is_list(responses) do
    key = {__MODULE__, self()}
    Process.put(key, responses)

    fn request ->
      case Process.get(key) do
        [next | rest] ->
          if rest == [] do
            Process.delete(key)
          else
            Process.put(key, rest)
          end

          execute_stub(next, request)

        [] ->
          raise "HTTP stub exhausted"

        nil ->
          raise "HTTP stub not initialised"
      end
    end
  end

  defp execute_stub(response, request) when is_function(response, 1), do: response.(request)
  defp execute_stub(response, _request), do: response
end
