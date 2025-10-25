defmodule TheoryCraft.Utils.Parsers do
  @moduledoc false

  import NimbleParsec

  ## Parsers

  # 18.08.2025 00:00:01.154 GMT+0200
  defparsec :dukascopy_time,
            integer(2)
            |> ignore(string("."))
            |> concat(integer(2))
            |> ignore(string("."))
            |> concat(integer(4))
            |> ignore(string(" "))
            |> concat(integer(2))
            |> ignore(string(":"))
            |> concat(integer(2))
            |> ignore(string(":"))
            |> concat(integer(2))
            |> ignore(string("."))
            |> concat(integer(3))
            |> ignore(string(" "))
            |> concat(string("GMT"))
            |> ignore(string("+"))
            |> concat(integer(4))
            |> eos()
            |> post_traverse(:join_dukascopy_time)

  ## Private functions

  defp join_dukascopy_time("" = rest, args, context, _position, _offset) do
    [timezone_offset, "GMT", microseconds, secs, minutes, hour, year, month, day] = args

    date = Date.new!(year, month, day)
    time = Time.new!(hour, minutes, secs, microseconds * 1000)
    datetime = DateTime.new!(date, time)

    # Calc timezone offset
    offset_hours = div(timezone_offset, 100)
    offset_minutes = rem(timezone_offset, 100)
    offset_seconds = offset_hours * 3600 + offset_minutes * 60

    # Apply timezone offset
    final = DateTime.add(datetime, -offset_seconds, :second)

    {rest, [final], context}
  end
end
