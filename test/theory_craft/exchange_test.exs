defmodule TheoryCraft.ExchangeTest do
  use ExUnit.Case, async: true

  defmodule DummyExchange do
    def history(symbol, timeframe, _opts) do
      {:ok, [symbol, timeframe]}
    end

    def live(symbols, _opts) do
      {:ok, symbols}
    end
  end

  test "history/4 forwards calls to the given exchange" do
    assert {:ok, ["BTC-USD", "1h"]} == TheoryCraft.Exchange.history(DummyExchange, "BTC-USD", "1h")
  end

  test "live/3 forwards calls to the given exchange" do
    assert {:ok, ["BTC-USD"]} == TheoryCraft.Exchange.live(DummyExchange, ["BTC-USD"])
  end
end
