defmodule TheoryCraft.Tick do
  @moduledoc """
  Represents a market tick with bid/ask prices and volumes.
  """

  @behaviour TheoryCraft.ETSSerializable

  alias __MODULE__

  defstruct [:time, :ask, :bid, :ask_volume, :bid_volume]

  @type t :: %__MODULE__{
          time: DateTime.t(),
          ask: float() | nil,
          bid: float() | nil,
          ask_volume: float() | nil,
          bid_volume: float() | nil
        }

  ## Internal API

  @doc false
  @impl true
  def to_tuple(%Tick{} = tick, precision \\ :millisecond) do
    %Tick{
      time: time,
      ask: ask,
      bid: bid,
      ask_volume: ask_volume,
      bid_volume: bid_volume
    } = tick

    {DateTime.to_unix(time, precision), ask, bid, ask_volume, bid_volume}
  end

  @doc false
  @impl true
  def from_tuple({time, ask, bid, ask_volume, bid_volume}, precision \\ :millisecond) do
    %Tick{
      time: DateTime.from_unix!(time, precision),
      ask: ask,
      bid: bid,
      ask_volume: ask_volume,
      bid_volume: bid_volume
    }
  end
end
