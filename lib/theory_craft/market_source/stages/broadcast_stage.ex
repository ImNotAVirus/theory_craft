defmodule TheoryCraft.MarketSource.Stages.BroadcastStage do
  @moduledoc """
  A GenStage producer_consumer that broadcasts events to multiple consumers.

  This stage acts as a pass-through that receives events from a single producer
  and broadcasts them to multiple consumers using `GenStage.BroadcastDispatcher`.

  Used internally by MarketSource to fan-out events to parallel processors.

  ## Examples

      {:ok, broadcast} = BroadcastStage.start_link(subscribe_to: [upstream])

      # Multiple consumers can subscribe and each will receive all events
      GenStage.sync_subscribe(consumer1, to: broadcast)
      GenStage.sync_subscribe(consumer2, to: broadcast)

  """

  use GenStage

  require Logger

  alias TheoryCraft.MarketSource.Stages.StageHelpers

  ## Public API

  @doc """
  Starts a BroadcastStage as a GenStage producer_consumer with BroadcastDispatcher.

  ## Parameters

    - `opts` - Keyword list of GenStage options (must include `:subscribe_to`).

  ## Returns

    - `{:ok, pid}` on success
    - `{:error, reason}` on failure
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    gen_stage_opts = StageHelpers.extract_gen_stage_opts(opts)
    GenStage.start_link(__MODULE__, opts, gen_stage_opts)
  end

  ## GenStage callbacks

  @impl true
  def init(opts) do
    Logger.debug("BroadcastStage starting")

    subscribe_to = Keyword.fetch!(opts, :subscribe_to)
    subscription_opts = StageHelpers.extract_subscription_opts(opts)
    state = StageHelpers.init_tracking_state()

    stage_opts =
      Keyword.merge(
        [subscribe_to: subscribe_to, dispatcher: GenStage.BroadcastDispatcher],
        subscription_opts
      )

    {:producer_consumer, state, stage_opts}
  end

  @impl true
  def handle_subscribe(:producer, _opts, from, state) do
    StageHelpers.handle_producer_subscribe(state, from)
  end

  @impl true
  def handle_subscribe(:consumer, _opts, from, state) do
    StageHelpers.handle_consumer_subscribe(state, from)
  end

  @impl true
  def handle_cancel(_reason, from, state) do
    StageHelpers.handle_cancel_with_termination(state, from, "BroadcastStage")
  end

  @impl true
  def handle_info(:stop, state) do
    StageHelpers.handle_stop_message(state)
  end

  @impl true
  def handle_events(events, _from, state) do
    # Just pass through all events
    {:noreply, events, state}
  end
end
