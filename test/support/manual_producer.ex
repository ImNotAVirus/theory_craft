defmodule TheoryCraft.TestHelpers.ManualProducer do
  @moduledoc """
  A GenStage producer for testing that sends events on explicit command.

  This producer doesn't automatically send events on demand - instead,
  events must be sent manually using `TheoryCraft.TestHelpers.send_events/2`.

  ## Examples

      # Start a manual producer
      {:ok, producer} = GenStage.start_link(TheoryCraft.TestHelpers.ManualProducer, %{events: []})

      # Send events manually
      TheoryCraft.TestHelpers.send_events(producer, [event1, event2])

  """
  use GenStage

  @doc false
  def init(state) do
    {:producer, state}
  end

  @doc false
  def handle_demand(_demand, state) do
    # Don't automatically send events, wait for manual send
    {:noreply, [], state}
  end

  @doc false
  def handle_call({:send_events, events}, _from, state) do
    {:reply, :ok, events, state}
  end
end
