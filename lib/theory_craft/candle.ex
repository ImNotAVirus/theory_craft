defmodule TheoryCraft.Candle do
  @moduledoc """
  Represents a market candle with open/high/low/close prices and volumes.
  """

  alias __MODULE__

  defstruct [
    :time,
    :open,
    :high,
    :low,
    :close,
    :volume,
    new_bar?: true,
    new_market?: false
  ]

  @type t :: %Candle{
          ## Base
          time: DateTime.t(),
          open: float() | nil,
          high: float() | nil,
          low: float() | nil,
          close: float() | nil,
          volume: float() | nil,
          ## Meta
          new_bar?: boolean(),
          new_market?: boolean()
        }
end
