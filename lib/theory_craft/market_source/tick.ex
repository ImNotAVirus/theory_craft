defmodule TheoryCraft.MarketSource.Tick do
  @moduledoc """
  Represents a market tick with bid/ask prices and volumes.
  """

  alias __MODULE__

  defstruct [:time, :ask, :bid, :ask_volume, :bid_volume]

  @type t :: %Tick{
          time: DateTime.t(),
          ask: float() | nil,
          bid: float() | nil,
          ask_volume: float() | nil,
          bid_volume: float() | nil
        }
end
