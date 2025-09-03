defmodule TheoryCraft.DataFeed do
  @moduledoc """
  TODO: Documentation
  """

  ## Public API

  def start_and_stream!(module, args) do
    {:ok, producer} = apply(module, :start_link, args)
    GenStage.stream([{producer, cancel: :transient}])
  end
end
