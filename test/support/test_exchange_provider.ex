defmodule TheoryCraft.TestProviders.ExchangeStub do
  @moduledoc false

  alias TheoryCraft.ExchangeData
  alias TheoryCraft.DataFeeds.ExchangeDataFeed.Provider

  @behaviour Provider

  @impl true
  def fetch_historical(opts) do
    {:ok, Keyword.get(opts, :historical_data, [])}
  end

  @impl true
  def start_live(opts) do
    batches = Keyword.get(opts, :live_batches, [])
    on_stop = Keyword.get(opts, :on_stop)

    {:ok, %{batches: batches, on_stop: on_stop}}
  end

  @impl true
  def fetch_live(%{batches: []} = state) do
    {:halt, state}
  end

  def fetch_live(%{batches: [batch | rest]} = state) when is_list(batch) do
    {:ok, {Enum.map(batch, &normalize_entry/1), %{state | batches: rest}}}
  end

  @impl true
  def stop_live(%{on_stop: fun}) when is_function(fun, 0) do
    fun.()
    :ok
  end

  def stop_live(_), do: :ok

  defp normalize_entry(%ExchangeData{} = entry), do: entry

  defp normalize_entry(attrs) when is_map(attrs) do
    struct!(ExchangeData, attrs)
  end
end

