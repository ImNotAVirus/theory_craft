defmodule TheoryCraft.ExchangeData do
  @moduledoc """
  Represents aggregated exchange metrics such as price and open interest.
  """

  alias __MODULE__

  defstruct [
    :time,
    :symbol,
    :price,
    :open_interest,
    :volume,
    :funding_rate
  ]

  @type t :: %ExchangeData{
          time: DateTime.t(),
          symbol: String.t() | nil,
          price: float() | nil,
          open_interest: float() | nil,
          volume: float() | nil,
          funding_rate: float() | nil
        }
end

