defmodule TheoryCraft.DataFeed do
  @moduledoc """
  A behaviour for data feeds.

  A data feed is responsible for providing a continuous stream of market events.
  """

  alias TheoryCraft.MarketEvent

  @callback stream(Keyword.t()) :: {:ok, Enumerable.t(MarketEvent.t())} | {:error, any()}
  @callback stream!(Keyword.t()) :: Enumerable.t(MarketEvent.t())

  ## Public API

  defmacro __using__(_opts) do
    quote do
      @behaviour TheoryCraft.DataFeed

      @impl true
      def stream!(opts) do
        case stream(opts) do
          {:ok, stream} -> stream
          {:error, reason} -> raise ArgumentError, "Failed to create stream: #{inspect(reason)}"
        end
      end

      defoverridable stream!: 1
    end
  end
end
