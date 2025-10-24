defmodule TheoryCraft.Exchange do
  @moduledoc """
  Handles fetching historical and live data from crypto exchanges.
  """

  def history(exchange, symbol, timeframe, opts \\ []) do
    exchange.history(symbol, timeframe, opts)
  end

  def live(exchange, symbols, opts \\ []) do
    exchange.live(symbols, opts)
  end
end
