defmodule TheoryCraft.MarketSource.MemoryDataFeed do
  @moduledoc """
  An in-memory data feed implementation.

  This module provides a way to store and stream market data
  to an in-memory ETS table.
  """

  use TheoryCraft.MarketSource.DataFeed

  alias __MODULE__
  alias TheoryCraft.MarketSource.{Bar, Tick}
  alias TheoryCraft.MarketSource.DataFeed

  defstruct [:table, :precision]

  @type t :: %MemoryDataFeed{table: :ets.tid(), precision: :native | System.time_unit()}

  ## Public API

  @doc """
  This function creates a new ETS table and fills it with data from the given data feed.

  ## Parameters

    - `enumerable`: The enumerable stream of data to be stored in the ETS table.
    - `time_precision`: The precision to use for timestamps in the data. 
      You can use `:auto` to guess the precision based on data.

  """
  @spec new(Enumerable.t(DataFeed.stream()), :auto | :native | System.time_unit()) :: t()
  def new(enumerable, time_precision \\ :auto) do
    table = create_ets_table()
    precision = get_precision(enumerable, time_precision)

    :ok = fill_table(table, enumerable, precision)

    %MemoryDataFeed{table: table, precision: precision}
  end

  @doc """
  Delete the ETS table.
  """
  @spec close(t()) :: :ok
  def close(%MemoryDataFeed{table: table}) do
    case :ets.info(table) do
      :undefined ->
        :ok

      _ ->
        :ets.delete(table)
        :ok
    end
  end

  ## DataFeed behaviour

  @impl true
  def stream(opts) do
    with {:ok, %MemoryDataFeed{} = df} <- Keyword.fetch(opts, :from) do
      %MemoryDataFeed{table: table, precision: precision} = df

      stream =
        Stream.resource(
          fn -> :ets.first(table) end,
          fn
            :"$end_of_table" ->
              {:halt, :"$end_of_table"}

            key ->
              case :ets.lookup(table, key) do
                [data] -> {[load(data, precision)], :ets.next(table, key)}
                [] -> {:halt, :"$end_of_table"}
              end
          end,
          fn _ -> :ok end
        )

      {:ok, stream}
    else
      :error -> {:error, ":from option is required"}
      {:ok, _} -> {:error, ":from option must be a MemoryDataFeed"}
    end
  end

  ## Private functions

  defp create_ets_table() do
    :ets.new(:memory_data_feed, [
      :ordered_set,
      :protected,
      :compressed,
      read_concurrency: true,
      write_concurrency: :auto
    ])
  end

  defp fill_table(table, enumerable, precision) do
    enumerable
    |> Enum.with_index()
    |> Enum.each(fn {bar, index} ->
      :ets.insert(table, dump(bar, index, precision))
    end)
  end

  defp get_precision(enumerable, :auto) do
    case Enum.take(enumerable, 1) do
      [] -> :millisecond
      # Tick or Bar struct
      [%{time: %DateTime{microsecond: {_, 0}}}] -> :second
      [%{time: %DateTime{microsecond: {_, 3}}}] -> :millisecond
      [%{time: %DateTime{microsecond: {_, 6}}}] -> :microsecond
    end
  end

  defp get_precision(_enumerable, precision) do
    precision
  end

  defp dump(%Tick{} = tick, _index, precision) do
    %Tick{
      time: time,
      ask: ask,
      bid: bid,
      ask_volume: ask_volume,
      bid_volume: bid_volume
    } = tick

    {DateTime.to_unix(time, precision), ask, bid, ask_volume, bid_volume}
  end

  defp dump(%Bar{} = bar, index, precision) do
    %Bar{
      time: time,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    } = bar

    {index, DateTime.to_unix(time, precision), open, high, low, close, volume}
  end

  defp load({time, ask, bid, ask_volume, bid_volume}, precision) do
    %Tick{
      time: DateTime.from_unix!(time, precision),
      ask: ask,
      bid: bid,
      ask_volume: ask_volume,
      bid_volume: bid_volume
    }
  end

  defp load({_index, time, open, high, low, close, volume}, precision) do
    %Bar{
      time: DateTime.from_unix!(time, precision),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    }
  end
end
