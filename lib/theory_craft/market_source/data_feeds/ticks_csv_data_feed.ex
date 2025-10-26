defmodule TheoryCraft.MarketSource.TicksCSVDataFeed do
  @moduledoc """
  A data feed for streaming CSV tick data.

  This module provides a way to stream Tick data from a CSV file,
  implementing the DataFeed behaviour.
  """

  use TheoryCraft.MarketSource.DataFeed

  alias NimbleCSV.RFC4180, as: CSV
  alias TheoryCraft.MarketSource.Tick
  alias TheoryCraft.Utils

  ## DataFeed behaviour

  @impl true
  def stream(opts) do
    case Keyword.fetch(opts, :file) do
      {:ok, file} ->
        skip_headers = Keyword.get(opts, :skip_headers, true)
        read_ahead = Keyword.get(opts, :read_ahead, 500_000)

        stream =
          file
          |> File.stream!(read_ahead: read_ahead)
          |> CSV.parse_stream(skip_headers: skip_headers)
          |> transform_csv_fun(skip_headers, opts)

        {:ok, stream}

      :error ->
        {:error, ":file option is required"}
    end
  end

  ## Private functions

  defp transform_csv_fun(stream, false = _skip_headers, opts) do
    time_format = Keyword.get(opts, :time_format, {:datetime, :millisecond, "Etc/UTC"})
    nil_value = Keyword.get(opts, :nil_value, "NaN")

    time = Keyword.get(opts, :time, 0)
    ask = Keyword.get(opts, :ask, 1)
    bid = Keyword.get(opts, :bid, 2)
    ask_volume = Keyword.get(opts, :ask_volume, 3)
    bid_volume = Keyword.get(opts, :bid_volume, 4)
    headers = [time: time, ask: ask, bid: bid, ask_volume: ask_volume, bid_volume: bid_volume]

    Stream.transform(stream, _headers = nil, fn
      row, nil ->
        {[], normalize_headers(headers, row)}

      row, headers_info ->
        struct = row_to_struct(row, headers_info, time_format, nil_value)
        {[struct], headers_info}
    end)
  end

  defp normalize_headers(headers, row) do
    find_index! = fn header ->
      Enum.find_index(row, &(header == &1)) || raise ArgumentError, "Header #{header} not found"
    end

    headers =
      for {name, value} <- headers, not is_nil(value), into: %{} do
        case value do
          value when is_integer(value) -> {value, name}
          value when is_binary(value) -> {find_index!.(value), name}
          _ -> raise ArgumentError, "Headers must be integers or binaries (got #{inspect(value)})"
        end
      end

    max_value = headers |> Map.keys() |> Enum.max()
    {headers, max_value}
  end

  defp row_to_struct(row, headers_info, time_format, nil_value) do
    row
    |> parse_row(headers_info)
    |> Enum.map(fn
      {:time, value} -> {:time, Utils.parse_datetime(value, time_format)}
      {key, value} -> {key, Utils.parse_float(value, nil_value)}
    end)
    |> then(&struct(Tick, &1))
  end

  defp parse_row(row, {headers, max_value}) do
    row
    |> Enum.with_index()
    |> Enum.reduce_while([], fn
      {_value, index}, acc when index > max_value ->
        {:halt, acc}

      {value, index}, acc ->
        case headers do
          %{^index => key} -> {:cont, [{key, value} | acc]}
          _ -> {:cont, acc}
        end
    end)
  end
end
