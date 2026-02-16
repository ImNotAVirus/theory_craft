defmodule TheoryCraft.TimeFrame do
  @moduledoc """
  Helpers for working with time frames.
  """

  @type unit :: String.t()
  @type multiplier :: non_neg_integer()
  @type t :: {unit(), multiplier()}

  @units ~w(t s m h D W M)

  ## Public API

  @doc """
  Parses a timeframe string or atom.

  ## Examples

      iex> TimeFrame.parse("m5")
      {:ok, {"m", 5}}

      iex> TimeFrame.parse(:h1)
      {:ok, {"h", 1}}

      iex> TimeFrame.parse("D")
      {:ok, {"D", 1}}

      iex> TimeFrame.parse("i12")
      {:error, {:invalid_unit, "i"}}
      
      iex> TimeFrame.parse("mI")
      {:error, {:invalid_multiplier, "I"}}
      
      iex> TimeFrame.parse("")
      {:error, :invalid_format}

  """
  @spec parse(timeframe) :: {:ok, t()} | {:error, reason}
        when timeframe: String.t() | atom(),
             reason:
               {:invalid_unit, String.t()}
               | {:invalid_multiplier, String.t()}
               | :invalid_format
  def parse(timeframe) do
    str = to_string(timeframe)

    with {:ok, unit} <- extract_unit(str),
         {:ok, mult} <- extract_multiplier(str) do
      {:ok, {unit, mult}}
    end
  end

  @doc """
  Parses a timeframe string or atom. Raises on invalid input.

  ## Examples

      iex> TimeFrame.parse!("m5")
      {"m", 5}

      iex> TimeFrame.parse!("x5")
      ** (ArgumentError) Invalid timeframe unit 'x'. Valid units are: t, s, m, h, D, W, M

  """
  @spec parse!(timeframe) :: t() when timeframe: String.t() | atom()
  def parse!(timeframe) do
    case parse(timeframe) do
      {:ok, result} ->
        result

      {:error, {:invalid_unit, unit}} ->
        all_units = Enum.join(@units, ", ")
        raise ArgumentError, "Invalid timeframe unit '#{unit}'. Valid units are: #{all_units}"

      {:error, {:invalid_multiplier, mult}} ->
        raise ArgumentError, "Invalid timeframe multiplier '#{mult}'. Must be a positive integer"

      {:error, :invalid_format} ->
        raise ArgumentError, "Invalid timeframe format #{inspect(timeframe)}"
    end
  end

  @doc """
  Checks if a timeframe string or atom is valid.

  ## Examples

      iex> TimeFrame.valid?("m5")
      true

      iex> TimeFrame.valid?(:h1)
      true

      iex> TimeFrame.valid?("invalid")
      false

  """
  @spec valid?(timeframe) :: boolean() when timeframe: String.t() | atom()
  def valid?(timeframe) do
    case parse(timeframe) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Returns the number of milliseconds for a given timeframe.

  Only works for timeframes with fixed durations: seconds (`s`), minutes (`m`),
  hours (`h`), days (`D`), and weeks (`W`). Ticks (`t`) have a variable duration
  and return an error.

  Months (`M`) use an approximate value of 30 days.

  ## Examples

      iex> TimeFrame.to_milliseconds({"s", 1})
      {:ok, 1_000}

      iex> TimeFrame.to_milliseconds({"s", 30})
      {:ok, 30_000}

      iex> TimeFrame.to_milliseconds({"m", 1})
      {:ok, 60_000}

      iex> TimeFrame.to_milliseconds({"m", 5})
      {:ok, 300_000}

      iex> TimeFrame.to_milliseconds({"h", 1})
      {:ok, 3_600_000}

      iex> TimeFrame.to_milliseconds({"h", 4})
      {:ok, 14_400_000}

      iex> TimeFrame.to_milliseconds({"D", 1})
      {:ok, 86_400_000}

      iex> TimeFrame.to_milliseconds({"W", 1})
      {:ok, 604_800_000}

      iex> TimeFrame.to_milliseconds({"W", 2})
      {:ok, 1_209_600_000}
      
      iex> TimeFrame.to_milliseconds({"M", 1})
      {:ok, 2_592_000_000}

      iex> TimeFrame.to_milliseconds({"M", 3})
      {:ok, 7_776_000_000}

      iex> TimeFrame.to_milliseconds({"t", 1})
      {:error, :variable_duration}

  """
  @spec to_milliseconds(t()) :: {:ok, non_neg_integer()} | {:error, :variable_duration}
  def to_milliseconds({unit, mult}) do
    case unit_to_milliseconds(unit) do
      {:ok, ms} -> {:ok, ms * mult}
      :error -> {:error, :variable_duration}
    end
  end

  ## Private functions

  defp extract_unit(str) do
    case str do
      <<unit::binary-size(1), _rest::binary>> when unit in @units -> {:ok, unit}
      <<unit::binary-size(1), _rest::binary>> -> {:error, {:invalid_unit, unit}}
      _ -> {:error, :invalid_format}
    end
  end

  defp extract_multiplier(str) do
    case str do
      <<_unit::binary-size(1)>> -> {:ok, 1}
      <<_unit::binary-size(1), mult_str::binary>> -> parse_multiplier(mult_str)
      _ -> {:error, :invalid_format}
    end
  end

  defp parse_multiplier(str) do
    case Integer.parse(str) do
      {mult, ""} when mult > 0 -> {:ok, mult}
      _ -> {:error, {:invalid_multiplier, str}}
    end
  end

  # :timer.seconds(1)
  defp unit_to_milliseconds("s"), do: {:ok, 1000}
  # :timer.minutes(1)
  defp unit_to_milliseconds("m"), do: {:ok, 60_000}
  # :timer.hours(1)
  defp unit_to_milliseconds("h"), do: {:ok, 3_600_000}
  # :timer.hours(24)
  defp unit_to_milliseconds("D"), do: {:ok, 86_400_000}
  # :timer.hours(24 * 7)
  defp unit_to_milliseconds("W"), do: {:ok, 604_800_000}
  # :timer.hours(24 * 30)
  defp unit_to_milliseconds("M"), do: {:ok, 2_592_000_000}
  defp unit_to_milliseconds(_), do: :error
end
