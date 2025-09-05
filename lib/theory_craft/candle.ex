defmodule TheoryCraft.Candle do
  @moduledoc """
  Represents a market candle with open/high/low/close prices and volumes.
  """

  @behaviour TheoryCraft.ETSSerializable

  alias __MODULE__

  defstruct [:time, :open, :high, :low, :close, :volume]

  @type t :: %__MODULE__{
          time: DateTime.t(),
          open: float() | nil,
          high: float() | nil,
          low: float() | nil,
          close: float() | nil,
          volume: float() | nil
        }

  ## Internal API

  @doc false
  @impl true
  def to_tuple(%Candle{} = candle, precision \\ :millisecond) do
    %Candle{
      time: time,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    } = candle

    {DateTime.to_unix(time, precision), open, high, low, close, volume}
  end

  @doc false
  @impl true
  def from_tuple({time, open, high, low, close, volume}, precision \\ :millisecond) do
    %Candle{
      time: DateTime.from_unix!(time, precision),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    }
  end
end
