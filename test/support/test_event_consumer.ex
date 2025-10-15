defmodule TheoryCraft.TestHelpers.TestEventConsumer do
  @moduledoc """
  A GenStage consumer for testing that forwards events to a test process.

  This consumer forwards all received events to a test process, optionally
  with a tag to identify which consumer sent them. It also handles producer
  cancellation to notify the test process when producers complete.

  ## Examples

      # Basic consumer that forwards events
      {:ok, consumer} = GenStage.start_link(
        TheoryCraft.TestHelpers.TestEventConsumer,
        test_pid: self()
      )

      # Consumer with tag for multiple consumers
      {:ok, consumer} = GenStage.start_link(
        TheoryCraft.TestHelpers.TestEventConsumer,
        test_pid: self(),
        tag: :consumer1
      )

      # Consumer with automatic subscription
      {:ok, consumer} = GenStage.start_link(
        TheoryCraft.TestHelpers.TestEventConsumer,
        test_pid: self(),
        subscribe_to: [{producer, max_demand: 10}]
      )

  """
  use GenStage

  @doc false
  def init(opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    tag = Keyword.get(opts, :tag)
    subscribe_to = Keyword.get(opts, :subscribe_to)

    state = %{test_pid: test_pid, tag: tag}

    if subscribe_to do
      {:consumer, state, subscribe_to: subscribe_to}
    else
      {:consumer, state}
    end
  end

  @doc false
  def handle_events(events, _from, state) do
    if state.tag do
      send(state.test_pid, {:events, state.tag, events})
    else
      send(state.test_pid, {:events, events})
    end

    {:noreply, [], state}
  end

  @doc false
  def handle_cancel({:down, :normal}, _from, state) do
    send(state.test_pid, {:producer_done, :normal})
    {:noreply, [], state}
  end

  @doc false
  def handle_cancel({:down, _reason}, _from, state) do
    {:noreply, [], state}
  end

  @doc false
  def handle_cancel(_reason, _from, state) do
    {:noreply, [], state}
  end
end
