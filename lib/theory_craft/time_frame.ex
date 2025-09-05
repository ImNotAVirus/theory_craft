defmodule TheoryCraft.TimeFrame do
  @moduledoc """
  Helpers for working with time frames.
  """

  @type unit :: String.t()
  @type multiplier :: non_neg_integer()
  @type t :: {unit(), multiplier()}

  @units ~w(t s m h D W M)

  ## Public API

  def parse!(timeframe) do
    {unit, mult} =
      case to_string(timeframe) do
        <<unit::binary-size(1)>> -> {unit, 1}
        <<unit::binary-size(1), mult::binary>> -> {unit, String.to_integer(mult)}
      end

    {validate_unit!(unit), mult}
  end

  ## Private functions

  defp validate_unit!(unit) do
    if unit in @units do
      unit
    else
      all_units = Enum.join(@units, ", ")
      raise ArgumentError, "Invalid timeframe unit '#{unit}'. Valid units are: #{all_units}"
    end
  end
end
