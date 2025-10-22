defmodule TheoryCraft.DataFeeds.ExchangeDataFeedTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataFeeds.ExchangeDataFeed
  alias TheoryCraft.ExchangeData
  alias TheoryCraft.TestProviders.ExchangeStub

  ## Tests

  describe "stream/1 historical mode" do
    test "emits historical snapshots from the provider" do
      historical_data = build_exchange_series()

      opts = [
        provider: ExchangeStub,
        mode: :historical,
        historical_data: historical_data
      ]

      assert {:ok, stream} = ExchangeDataFeed.stream(opts)
      assert Enum.to_list(stream) == historical_data
    end

    test "returns error when provider lacks historical callback" do
      opts = [
        provider: OnlyLiveProvider,
        mode: :historical
      ]

      assert {:error, {:provider_missing_callback, :fetch_historical}} =
               ExchangeDataFeed.stream(opts)
    end
  end

  describe "stream/1 live mode" do
    test "emits live batches and stops provider" do
      batches = [
        [
          %{time: ~U[2024-01-01 00:00:00Z], symbol: "BTC", price: 42_000.0},
          %{time: ~U[2024-01-01 00:00:10Z], symbol: "BTC", price: 42_010.0}
        ],
        [
          %{time: ~U[2024-01-01 00:00:20Z], symbol: "BTC", price: 42_020.0}
        ]
      ]

      parent = self()
      on_stop = fn -> send(parent, :stopped) end

      opts = [
        provider: ExchangeStub,
        mode: :live,
        poll_interval: 0,
        live_batches: batches,
        on_stop: on_stop
      ]

      assert {:ok, stream} = ExchangeDataFeed.stream(opts)
      events = Enum.to_list(stream)

      assert length(events) == 3
      assert Enum.all?(events, &match?(%ExchangeData{}, &1))
      assert_received :stopped
    end

    test "raises when provider returns live error" do
      opts = [
        provider: ErrorLiveProvider,
        mode: :live
      ]

      assert {:ok, stream} = ExchangeDataFeed.stream(opts)

      assert_raise RuntimeError, ~r/Exchange live fetch failed/, fn ->
        Enum.to_list(stream)
      end
    end
  end

  describe "stream/1 both mode" do
    test "emits historical snapshots followed by live updates" do
      historical = build_exchange_series()

      live_batches = [
        [
          %{time: ~U[2024-01-01 00:03:00Z], symbol: "ETH", price: 3_200.0}
        ]
      ]

      opts = [
        provider: ExchangeStub,
        mode: :both,
        poll_interval: 0,
        historical_data: historical,
        live_batches: live_batches
      ]

      assert {:ok, stream} = ExchangeDataFeed.stream(opts)
      events = Enum.to_list(stream)

      assert Enum.take(events, length(historical)) == historical
      assert List.last(events).symbol == "ETH"
    end
  end

  describe "invalid configuration" do
    test "returns error for unsupported mode" do
      opts = [provider: ExchangeStub, mode: :unknown]
      assert {:error, {:invalid_mode, :unknown}} = ExchangeDataFeed.stream(opts)
    end

    test "errors when provider missing live callbacks" do
      opts = [provider: ExchangeStub, mode: :live]

      # Temporarily redefine provider to remove live callbacks
      assert {:error, {:provider_missing_callback, :start_live}} =
               ExchangeDataFeed.stream(Keyword.put(opts, :provider, HistoricalOnlyProvider))
    end

    test "errors when neither historical nor live requested" do
      assert {:error, {:invalid_mode, :off}} =
               ExchangeDataFeed.stream(provider: ExchangeStub, mode: :off)
    end
  end

  ## Helper modules (test-only)

  defmodule OnlyLiveProvider do
    @moduledoc false
    @behaviour ExchangeDataFeed.Provider

    @impl true
    def start_live(_opts), do: {:ok, []}

    @impl true
    def fetch_live([]), do: {:halt, []}
  end

  defmodule HistoricalOnlyProvider do
    @moduledoc false
    @behaviour ExchangeDataFeed.Provider

    @impl true
    def fetch_historical(_opts), do: {:ok, []}
  end

  defmodule ErrorLiveProvider do
    @moduledoc false
    @behaviour ExchangeDataFeed.Provider

    @impl true
    def start_live(_opts), do: {:ok, :state}

    @impl true
    def fetch_live(:state), do: {:error, :boom}
  end

  ## Helpers

  defp build_exchange_series() do
    [
      %ExchangeData{
        time: ~U[2024-01-01 00:00:00Z],
        symbol: "BTC",
        price: 42_000.0,
        open_interest: 120_000.0,
        volume: 900.0,
        funding_rate: 0.0001
      },
      %ExchangeData{
        time: ~U[2024-01-01 00:01:00Z],
        symbol: "BTC",
        price: 42_050.0,
        open_interest: 121_000.0,
        volume: 850.0,
        funding_rate: 0.00012
      }
    ]
  end
end

