defmodule TheoryCraft.DataFeeds.MemoryDataFeed do
  @moduledoc """
  A GenStage producer for streaming in-memory data.

  This module provides a way to create a GenStage producer that streams
  data from an in-memory ETS table.
  """

  use TheoryCraft.DataFeed

  alias __MODULE__
  alias TheoryCraft.{Candle, Tick}
  alias TheoryCraft.MarketEvent

  defstruct [:table, :precision]

  @type t :: %MemoryDataFeed{table: :ets.tid(), precision: :native | System.time_unit()}

  ## Public API

  @doc """
  This function creates a new ETS table and fills it with data from the given data feed.
  """
  @spec new(pid() | Enumerable.t(MarketEvent.data()), :native | System.time_unit()) :: t()
  def new(data_feed, time_precision \\ :millisecond)

  def new(data_feed, time_precision) when is_pid(data_feed) do
    table = create_ets_table()

    enumerable = GenStage.stream([{data_feed, cancel: :transient}])
    :ok = fill_table(table, enumerable, time_precision)

    %MemoryDataFeed{table: table, precision: time_precision}
  end

  def new(enumerable, time_precision) do
    table = create_ets_table()

    :ok = fill_table(table, enumerable, time_precision)

    %MemoryDataFeed{table: table, precision: time_precision}
  end

  @doc """
  Delete the ETS table.
  """
  @spec close(t()) :: :ok
  def close(%MemoryDataFeed{table: table}) do
    true = :ets.delete(table)
    :ok
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
    |> Enum.each(fn {candle, index} ->
      :ets.insert(table, dump(candle, index, precision))
    end)
  end

  defp dump(%MarketEvent{tick_or_candle: tick_or_candle}, index, precision) do
    dump(tick_or_candle, index, precision)
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

  defp dump(%Candle{} = candle, index, precision) do
    %Candle{
      time: time,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    } = candle

    {index, DateTime.to_unix(time, precision), open, high, low, close, volume}
  end

  defp load({time, ask, bid, ask_volume, bid_volume}, precision) do
    %MarketEvent{
      tick_or_candle: %Tick{
        time: DateTime.from_unix!(time, precision),
        ask: ask,
        bid: bid,
        ask_volume: ask_volume,
        bid_volume: bid_volume
      }
    }
  end

  defp load({_index, time, open, high, low, close, volume}, precision) do
    %MarketEvent{
      tick_or_candle: %Candle{
        time: DateTime.from_unix!(time, precision),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume
      }
    }
  end
end
