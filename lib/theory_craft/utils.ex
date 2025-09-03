defmodule TheoryCraft.Utils do
  @moduledoc false

  require TheoryCraft.Utils.Parsers, as: Parsers

  ## Public API

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
end
