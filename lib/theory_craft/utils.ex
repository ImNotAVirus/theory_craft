defmodule TheoryCraft.Utils do
  @moduledoc false
  ## Internal helpers

  require TheoryCraft.Utils.Parsers, as: Parsers

  ## Public API

  @doc """
  Normalizes a spec to a `{module, opts}` tuple.

  A spec can be either:
  - A module atom (e.g., `MyModule`) → normalized to `{MyModule, []}`
  - A tuple `{module, opts}` → returned as-is

  ## Parameters

    - `spec`: Either a module atom or a `{module, opts}` tuple

  ## Returns

  A `{module, opts}` tuple

  ## Examples

      iex> TheoryCraft.Utils.normalize_spec(MyModule)
      {MyModule, []}

      iex> TheoryCraft.Utils.normalize_spec({MyModule, [option: :value]})
      {MyModule, [option: :value]}

  """
  @spec normalize_spec(module() | {module(), Keyword.t()}) :: {module(), Keyword.t()}
  def normalize_spec(spec) do
    case spec do
      module when is_atom(module) -> {module, []}
      {module, opts} = tuple when is_atom(module) and is_list(opts) -> tuple
      _ -> raise ArgumentError, "Invalid spec: #{inspect(spec)}"
    end
  end

  def genserver_opts(opts) do
    Keyword.take(opts, ~w(debug name timeout spawn_opt hibernate_after)a)
  end

  def parse_float(value, nil_value) do
    case value do
      ^nil_value ->
        nil

      _ ->
        {float, ""} = Float.parse(value)
        float
    end
  end

  def parse_datetime(value, {:datetime, precision, timezone}) do
    value
    |> String.to_integer()
    |> DateTime.from_unix!(precision)
    |> DateTime.shift_zone!(timezone)
  end

  def parse_datetime(value, fun) when is_function(fun, 1) do
    fun.(value)
  end

  def parse_datetime(value, :dukascopy) do
    {:ok, [datetime], _, _, _, _} = Parsers.dukascopy_time(value)
    datetime
  end

  def duration_ms_to_string(value) do
    case value do
      v when v >= 60_000 ->
        mins = div(v, :timer.minutes(1))
        secs = div(v - mins * :timer.minutes(1), :timer.seconds(1))
        "#{mins}mins #{secs}secs"

      v when v >= 1_000 ->
        secs = div(v, :timer.seconds(1))
        ms = v - secs * :timer.seconds(1)
        "#{secs}secs #{ms}ms"

      _ ->
        "#{value}ms"
    end
  end

  def has_behaviour(module, behaviour) do
    attributes = module.module_info(:attributes)

    attributes
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.any?(&(&1 == behaviour))
  end

  def required_opt!(opts, name) do
    case Keyword.fetch(opts, name) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Missing required option: #{name} in #{inspect(opts)}"
    end
  end
end
