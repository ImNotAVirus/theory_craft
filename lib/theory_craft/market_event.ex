defmodule TheoryCraft.MarketEvent do
  @moduledoc """
  Represents a market event containing a tick or bar and associated metadata.
  """

  alias __MODULE__

  defstruct data: %{}

  @type t :: %MarketEvent{data: map()}
end
