defmodule TheoryCraft.DataFeeds.MemoryDataFeed do
  @moduledoc """
  A GenStage producer for streaming in-memory data.

  This module provides a way to create a GenStage producer that streams
  data from an in-memory ETS table.
  """

  alias __MODULE__
  alias TheoryCraft.Tick

  defstruct [:table, :precision]

  @type t :: %MemoryDataFeed{table: :ets.tid(), precision: :native | System.time_unit()}

  ## Public API

  @doc """
  This function creates a new ETS table and fills it with data from the given data feed.
  """
  @spec new(pid(), :native | System.time_unit()) :: t()
  def new(data_feed, time_precision \\ :millisecond) when is_pid(data_feed) do
    table = create_ets_table()

    enumerable = GenStage.stream([{data_feed, cancel: :transient}])
    :ok = fill_table(table, enumerable, time_precision)

    %MemoryDataFeed{table: table, precision: time_precision}
  end

  @spec start_link(t(), Keyword.t()) :: GenServer.on_start()
  def start_link(%MemoryDataFeed{} = df, opts \\ []) do
    %MemoryDataFeed{table: table, precision: precision} = df
    genserver_opts = Keyword.take(opts, ~w(debug name timeout spawn_opt hibernate_after)a)

    Stream.resource(
      fn -> :ets.first(table) end,
      fn
        :"$end_of_table" ->
          {:halt, :"$end_of_table"}

        key ->
          case :ets.lookup(table, key) do
            # FIXME: Find a way to dynamically handle the struct
            [{^key, _ask, _bid, _ask_volume, _bid_volume} = tuple] ->
              next_key = :ets.next(table, key)
              tick = Tick.from_tuple(tuple, precision)
              {[tick], next_key}

            [] ->
              {:halt, :"$end_of_table"}
          end
      end,
      fn _ -> :ok end
    )
    |> GenStage.from_enumerable([on_cancel: :stop] ++ genserver_opts)
  end

  @doc """
  Delete the ETS table.
  """
  @spec close(t()) :: :ok
  def close(%MemoryDataFeed{table: table}) do
    true = :ets.delete(table)
    :ok
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
    Enum.each(enumerable, fn %struct{} = tick_or_bar ->
      :ets.insert(table, struct.to_tuple(tick_or_bar, precision))
    end)
  end
end
