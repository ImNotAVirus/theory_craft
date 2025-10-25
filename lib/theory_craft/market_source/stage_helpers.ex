defmodule TheoryCraft.MarketSource.StageHelpers do
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
      %{producers: %{}, consumers: %{}},
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

        log_producer_cancelled(stage_name, map_size(new_producers))

        if map_size(new_producers) == 0 do
          # Last producer cancelled, stop this stage
          log_last_producer_cancelled(stage_name)
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

  @doc """
  Extracts GenStage and GenServer options from a keyword list.

  Returns a keyword list containing only valid GenStage/GenServer options:
  - `:name` - Register the stage with a name
  - `:timeout` - Timeout for GenServer.start_link
  - `:debug` - Debug options
  - `:spawn_opt` - Options for spawning the process
  - `:hibernate_after` - Hibernate after inactivity

  All other options are assumed to be stage-specific and are not included.

  ## Examples

      iex> extract_gen_stage_opts([name: :my_stage, timeout: 5000, custom: :opt])
      [name: :my_stage, timeout: 5000]

  """
  def extract_gen_stage_opts(opts) do
    Keyword.take(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])
  end

  @doc """
  Extracts GenStage subscription options from a keyword list.

  Returns a keyword list containing only valid subscription options:
  - `:min_demand` - Minimum demand (default depends on stage type)
  - `:max_demand` - Maximum demand (default depends on stage type)
  - `:buffer_size` - Size of the buffer (default: 10000)
  - `:buffer_keep` - Whether to keep the buffer (:first or :last, default: :last)

  All other options are assumed to be stage-specific and are not included.

  ## Examples

      iex> extract_subscription_opts([min_demand: 5, max_demand: 100, custom: :opt])
      [min_demand: 5, max_demand: 100]

  """
  def extract_subscription_opts(opts) do
    Keyword.take(opts, [:min_demand, :max_demand, :buffer_size, :buffer_keep])
  end

  ## Private helper functions

  defp log_producer_cancelled(nil, _remaining), do: :ok

  defp log_producer_cancelled(stage_name, remaining) do
    Logger.debug("#{stage_name}: Producer cancelled, #{remaining} remaining")
  end

  defp log_last_producer_cancelled(nil), do: :ok

  defp log_last_producer_cancelled(stage_name) do
    Logger.debug("#{stage_name}: Last producer cancelled, stopping")
  end
end
