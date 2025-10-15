defmodule TheoryCraft.TestHelpers do
  @moduledoc """
  Helper functions for testing GenStage pipelines.

  Provides utilities for manually controlling test producers and consumers.
  """

  @doc """
  Sends events to a ManualProducer.

  ## Parameters

    - `producer` - The PID of a `TheoryCraft.TestHelpers.ManualProducer`
    - `events` - A list of events to send

  ## Examples

      {:ok, producer} = GenStage.start_link(TheoryCraft.TestHelpers.ManualProducer, %{events: []})
      TheoryCraft.TestHelpers.send_events(producer, [event1, event2])

  """
  @spec send_events(pid(), [any()]) :: :ok
  def send_events(producer, events) do
    GenStage.call(producer, {:send_events, events})
  end
end
