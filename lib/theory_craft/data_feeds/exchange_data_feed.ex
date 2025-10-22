defmodule TheoryCraft.DataFeeds.ExchangeDataFeed do
  @moduledoc """
  Streams exchange metrics using pluggable provider callbacks.

  The feed supports three modes:
    * `:historical` – emits only historical snapshots
    * `:live` – emits only live updates
    * `:both` – emits historical data first, then switches to live updates

  A provider module must implement the callbacks defined in `Provider`. Different
  providers can wrap APIs, databases, or websockets while reusing this feed.
  """

  use TheoryCraft.DataFeed

  alias TheoryCraft.{ExchangeData, Utils}

  @typedoc """
  Valid stream modes.
  """
  @type mode :: :historical | :live | :both

  @default_poll_interval 1_000

  defmodule Provider do
    @moduledoc """
    Behaviour for modules that supply exchange metrics to `ExchangeDataFeed`.
    """

    @callback fetch_historical(Keyword.t()) ::
                {:ok, Enumerable.t(ExchangeData.t()) | nil} | {:error, term()}
    @callback start_live(Keyword.t()) :: {:ok, term()} | {:error, term()}
    @callback fetch_live(term()) ::
                {:ok, {[ExchangeData.t()], term()}} | {:halt, term()} | {:error, term()}
    @callback stop_live(term()) :: :ok

    @optional_callbacks fetch_historical: 1, start_live: 1, fetch_live: 1, stop_live: 1
  end

  ## DataFeed behaviour

  @impl true
  def stream(opts) do
    provider = Utils.required_opt!(opts, :provider)
    mode = Keyword.get(opts, :mode, :historical)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)

    case mode do
      :historical ->
        with {:ok, historical_stream} <- build_historical_stream(provider, opts) do
          {:ok, historical_stream}
        end

      :live ->
        with {:ok, live_stream} <- build_live_stream(provider, opts, poll_interval) do
          {:ok, live_stream}
        end

      :both ->
        with {:ok, historical_stream} <- build_historical_stream(provider, opts),
             {:ok, live_stream} <- build_live_stream(provider, opts, poll_interval) do
          {:ok, Stream.concat(historical_stream, live_stream)}
        end

      other ->
        {:error, {:invalid_mode, other}}
    end
  end

  ## Helpers

  defp build_historical_stream(provider, opts) do
    case call_provider(provider, :fetch_historical, [opts]) do
      {:ok, {:ok, enumerable}, _resolved_provider} ->
        enumerable = enumerable || []

        with :ok <- ensure_enumerable(enumerable) do
          {:ok, enumerable_to_stream(enumerable)}
        end

      {:ok, {:error, reason}, _resolved_provider} ->
        {:error, {:historical_error, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_live_stream(provider, opts, poll_interval) do
    case call_provider(provider, :start_live, [opts]) do
      {:ok, {:ok, state}, resolved_provider} ->
        if function_exported?(resolved_provider, :fetch_live, 1) do
          {:ok, live_resource_stream(resolved_provider, state, poll_interval)}
        else
          maybe_stop_provider(resolved_provider, state)
          {:error, {:provider_missing_callback, :fetch_live}}
        end

      {:ok, {:error, reason}, _resolved_provider} ->
        {:error, {:live_error, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp live_resource_stream(provider, initial_state, poll_interval) do
    Stream.resource(
      fn -> {:running, initial_state} end,
      fn
        {:halted, state} ->
          {:halt, state}

        {:running, state} ->
          case provider.fetch_live(state) do
            {:ok, {events, new_state}} when is_list(events) ->
              if events == [] and poll_interval > 0 do
                Process.sleep(poll_interval)
              end

              {events, {:running, new_state}}

            {:halt, final_state} ->
              {:halt, {:halted, final_state}}

            {:error, reason} ->
              raise RuntimeError, "Exchange live fetch failed: #{inspect(reason)}"
          end
      end,
      fn
        {:running, state} -> maybe_stop_provider(provider, state)
        {:halted, state} -> maybe_stop_provider(provider, state)
      end
    )
  end

  defp maybe_stop_provider(provider, state) do
    if function_exported?(provider, :stop_live, 1) do
      provider.stop_live(state)
    else
      :ok
    end
  end

  defp ensure_enumerable(enumerable) do
    if Enumerable.impl_for(enumerable) do
      :ok
    else
      {:error, {:non_enumerable_historical, enumerable}}
    end
  end

  defp enumerable_to_stream(enumerable) do
    enumerable |> Stream.map(& &1)
  end

  defp call_provider(provider, fun, args, tried_fallback \\ false) do
    try do
      {:ok, apply(provider, fun, args), provider}
    rescue
      error in [UndefinedFunctionError] ->
        handle_undefined_callback(provider, fun, args, error, __STACKTRACE__, tried_fallback)
    end
  end

  defp handle_undefined_callback(provider, fun, args, error, stacktrace, false)
       when error.module == provider and error.function == fun and
              error.arity == length(args) do
    with {:ok, alternate_provider} <- resolve_nested_provider(provider, fun, args, stacktrace) do
      call_provider(alternate_provider, fun, args, true)
    else
      _ -> {:error, {:provider_missing_callback, fun}}
    end
  end

  defp handle_undefined_callback(provider, fun, _args, error, stacktrace, _tried_fallback) do
    if error.module == provider and error.function == fun do
      {:error, {:provider_missing_callback, fun}}
    else
      reraise(error, stacktrace)
    end
  end

  defp resolve_nested_provider(provider, fun, args, stacktrace) do
    case Module.split(provider) do
      [_single_segment] ->
        arity = length(args)

        stacktrace
        |> Enum.map(&elem(&1, 0))
        |> Enum.find_value(fn module ->
          cond do
            not is_atom(module) ->
              nil

            module in [__MODULE__, Kernel, :erlang, :elixir, :elixir_eval] ->
              nil

            true ->
              candidate = Module.concat(module, provider)

              if Code.ensure_loaded?(candidate) and function_exported?(candidate, fun, arity) do
                {:ok, candidate}
              else
                nil
              end
          end
        end)
        |> case do
          {:ok, candidate} -> {:ok, candidate}
          nil -> :error
        end

      _ ->
        :error
    end
  end
end
