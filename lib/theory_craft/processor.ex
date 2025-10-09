defmodule TheoryCraft.Processor do
  @moduledoc """
  A module for processing market data.
  """

  alias TheoryCraft.MarketEvent

  @callback init(opts :: Keyword.t()) :: {:ok, state :: any()}
  @callback next(event :: MarketEvent.t(), state :: any()) ::
              {:ok, updated_event :: MarketEvent.t(), new_state :: any()}
end
