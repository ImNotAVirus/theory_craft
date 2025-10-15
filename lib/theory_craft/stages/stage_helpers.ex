defmodule TheoryCraft.Stages.StageHelpers do
  @moduledoc false
  # Internal helper functions for GenStage stages to reduce code duplication.
  #
  # Provides common functionality for tracking producers/consumers and handling
  # cancellations with the Flow termination pattern.

  require Logger

  @doc """
  Creates initial state with producer and consumer tracking maps.
  """
  def init_tracking_state(additional_state \\ %{}) do
    Map.merge(
      %{
        producers: %{},
        consumers: %{}
      },
      additional_state
    )
  end

  @doc """
  Handles producer subscription by tracking the producer reference.
  Returns `{:automatic, new_state}` or `{:manual, new_state}`.
  """
  def handle_producer_subscribe(state, from, demand_mode \\ :automatic) do
    {_pid, ref} = from
    new_state = update_in(state.producers, &Map.put(&1, ref, true))
    {demand_mode, new_state}
  end

  @doc """
  Handles consumer subscription by tracking the consumer reference.
  Returns `{:automatic, new_state}`.
  """
  def handle_consumer_subscribe(state, from) do
    {_pid, ref} = from
    new_state = update_in(state.consumers, &Map.put(&1, ref, true))
    {:automatic, new_state}
  end

  @doc """
  Handles cancellation with Flow termination pattern.

  When the last producer cancels:
  - Sends async :stop message to self
  - Returns `{:noreply, [], new_state}`

  When the last consumer cancels:
  - Returns `{:stop, :normal, state}`

  Otherwise:
  - Returns `{:noreply, [], new_state}` with updated tracking
  """
  def handle_cancel_with_termination(state, from, stage_name \\ nil) do
    {_pid, ref} = from
    %{producers: producers, consumers: consumers} = state

    case {producers, consumers} do
      {%{^ref => _}, _consumers} ->
        # Producer cancelled
        new_producers = Map.delete(producers, ref)

        if stage_name do
          Logger.debug("#{stage_name}: Producer cancelled, #{map_size(new_producers)} remaining")
        end

        if map_size(new_producers) == 0 do
          # Last producer cancelled, stop this stage
          if stage_name, do: Logger.debug("#{stage_name}: Last producer cancelled, stopping")
          GenStage.async_info(self(), :stop)
        end

        {:noreply, [], %{state | producers: new_producers}}

      {_producers, %{^ref => _}} ->
        # Consumer cancelled
        new_consumers = Map.delete(consumers, ref)

        if map_size(new_consumers) == 0 do
          # Last consumer cancelled, stop this stage
          {:stop, :normal, state}
        else
          {:noreply, [], %{state | consumers: new_consumers}}
        end
    end
  end

  @doc """
  Handles the :stop message by stopping the stage normally.
  """
  def handle_stop_message(state, stage_name \\ nil) do
    if stage_name, do: Logger.debug("#{stage_name} stopping normally")
    {:stop, :normal, state}
  end
end
