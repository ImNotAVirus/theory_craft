defmodule TheoryCraft.MarketEvent do
  @moduledoc """
  Represents a market event containing a tick or candle and associated metadata.
  """

  alias __MODULE__
  alias TheoryCraft.{Candle, Tick}

  @enforce_keys [:tick_or_candle]
  defstruct tick_or_candle: nil, data: %{}

  @type data :: Candle.t() | Tick.t()
  @type t :: %MarketEvent{tick_or_candle: data(), data: map()}
end
