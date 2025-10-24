defmodule TheoryCraft.DataFeeds.ExchangeCSVDataFeed do
  @moduledoc """
  A data feed for streaming exchange metrics (price, open interest, volume, etc.) from CSV files.
  """

  use TheoryCraft.DataFeed

  alias NimbleCSV.RFC4180, as: CSV
  alias TheoryCraft.{ExchangeData, Utils}

  ## DataFeed behaviour

  @impl true
  def stream(opts) do
    with {:ok, file} <- Keyword.fetch(opts, :file) do
      skip_headers = Keyword.get(opts, :skip_headers, true)
      read_ahead = Keyword.get(opts, :read_ahead, 500_000)

      stream =
        file
        |> File.stream!(read_ahead: read_ahead)
        |> CSV.parse_stream(skip_headers: skip_headers)
        |> transform_csv_fun(skip_headers, opts)

      {:ok, stream}
    else
      :error -> {:error, ":file option is required"}
    end
  end

  ## Private functions

  defp transform_csv_fun(stream, _skip_headers = false, opts) do
    time_format = Keyword.get(opts, :time_format, {:datetime, :millisecond, "Etc/UTC"})
    nil_value = Keyword.get(opts, :nil_value, "NaN")

    time = Keyword.get(opts, :time, 0)
    symbol = Keyword.get(opts, :symbol, 1)
    price = Keyword.get(opts, :price, 2)
    open_interest = Keyword.get(opts, :open_interest, 3)
    volume = Keyword.get(opts, :volume, 4)
    funding_rate = Keyword.get(opts, :funding_rate, 5)

    headers =
      [
        time: time,
        symbol: symbol,
        price: price,
        open_interest: open_interest,
        volume: volume,
        funding_rate: funding_rate
      ]

    Stream.transform(stream, _headers = nil, fn
      row, nil ->
        {[], normalize_headers(headers, row)}

      row, headers_info ->
        struct = row_to_struct(row, headers_info, time_format, nil_value)
        {[struct], headers_info}
    end)
  end

  defp transform_csv_fun(stream, _skip_headers = true, opts) do
    time_format = Keyword.get(opts, :time_format, {:datetime, :millisecond, "Etc/UTC"})
    nil_value = Keyword.get(opts, :nil_value, "NaN")

    headers_info =
      headers_from_indexes(opts, [
        time: 0,
        symbol: 1,
        price: 2,
        open_interest: 3,
        volume: 4,
        funding_rate: 5
      ])

    Stream.map(stream, fn row ->
      row_to_struct(row, headers_info, time_format, nil_value)
    end)
  end

  defp headers_from_indexes(opts, defaults) do
    headers =
      for {key, default} <- defaults,
          value = Keyword.get(opts, key, default),
          not is_nil(value),
          into: %{} do
        case value do
          value when is_integer(value) -> {value, key}
          _ -> raise ArgumentError, "Headers must be integers when skip_headers is true"
        end
      end

    case Map.keys(headers) do
      [] -> raise ArgumentError, "At least one column must be configured"
      keys -> {headers, Enum.max(keys)}
    end
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
    |> Enum.reduce([], fn
      {:time, value}, acc ->
        [{:time, Utils.parse_datetime(value, time_format)} | acc]

      {key, value}, acc when key in [:price, :open_interest, :volume, :funding_rate] ->
        [{key, Utils.parse_float(value, nil_value)} | acc]

      {key, value}, acc ->
        [{key, value} | acc]
    end)
    |> then(&struct(ExchangeData, &1))
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
