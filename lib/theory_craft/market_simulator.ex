defmodule TheoryCraft.MarketSimulator do
  @moduledoc """
  TODO: Documentation

  Currently the simulator only supports one data feed at a time.
  Later versions will support multiple data feeds.
  """

  alias __MODULE__
  alias TheoryCraft.MarketEvent
  alias TheoryCraft.TimeFrame
  alias TheoryCraft.Processors.TickToCandleProcessor
  alias TheoryCraft.DataFeeds.TicksCSVDataFeed

  defstruct data: %{}, processors: [], indicator: %{}, broker: nil

  @type processor :: {module(), opts :: Keyword.t()}

  @type t :: %MarketSimulator{
          data: %{any() => Enumerable.t(MarketEvent.t())},
          processors: [{data :: any(), processor :: processor()}],
          indicator: map(),
          broker: any()
        }

  # %MarketSimulator{}
  # |> add_data(stream, name: "xauusd_ticks")
  # # |> add_data("tick_xauusd.csv", name: "xauusd_ticks")
  # |> add_data("tick_xauusd.csv")
  # |> resample("m5")
  # |> resample("D", data: 0, name: "xauusd_daily")
  # |> add_indicator(TheoryCraft.Indicators.SMA, period: 14, name: "sma_14")
  # |> add_indicator(TheoryCraft.Indicators.Supertrend, period: 14, name: "supertrend_14", data: 0)
  # |> add_strategy(TheoryCraft.Strategies.MyStrategy)
  # |> set_balance(100_000)
  # |> set_commission(0.001)

  ## Public API

  @doc """
  Adds a data stream to the market simulator.

  ## Parameters

    - `simulator`: The market simulator.
    - `stream`: The data stream to add.
    - `opts`: Optional parameters, including a name for the data stream.

  """
  @spec add_data(t(), Enumerable.t(), Keyword.t()) :: t()
  def add_data(%MarketSimulator{} = simulator, stream, opts \\ []) do
    %MarketSimulator{data: data} = simulator

    stream = validate_stream!(stream)

    if map_size(data) > 0 do
      raise ArgumentError, "Currently only one data feed is supported"
    end

    name = Keyword.get_lazy(opts, :name, fn -> map_size(data) end)
    %MarketSimulator{simulator | data: Map.put(data, name, stream)}
  end

  @doc """
  Adds a data stream from a CSV file containing tick data.

  ## Parameters

    - `simulator`: The market simulator.
    - `file_path`: The path to the CSV file.
    - `opts`: Optional parameters for the data stream.

  """
  @spec add_data_ticks_from_csv(t(), String.t(), Keyword.t()) :: t()
  def add_data_ticks_from_csv(%MarketSimulator{} = simulator, file_path, opts \\ []) do
    stream = TicksCSVDataFeed.stream!([file: file_path] ++ opts)
    add_data(simulator, stream, opts)
  end

  @doc """
  Resamples the data in the market simulator to a different timeframe.

  ## Parameters

    - `simulator`: The market simulator.
    - `timeframe`: The new timeframe to resample the data to.
    - `opts`: Optional parameters, including the name of the data stream to resample.

  """
  @spec resample(t(), String.t(), Keyword.t()) :: t()
  def resample(%MarketSimulator{} = simulator, timeframe, opts \\ []) do
    %MarketSimulator{data: data, processors: processors} = simulator

    if not TimeFrame.valid?(timeframe) do
      raise ArgumentError, "Invalid timeframe #{inspect(timeframe)}"
    end

    data_name = Keyword.get_lazy(opts, :data, fn -> fetch_default_data_name(simulator) end)

    if not Map.has_key?(data, data_name) do
      raise ArgumentError, "Data stream #{inspect(data_name)} not found"
    end

    opts =
      opts
      |> Keyword.put(:timeframe, timeframe)
      |> Keyword.put(:data, data_name)

    processor = {TickToCandleProcessor, opts}

    %MarketSimulator{simulator | processors: [{data_name, processor} | processors]}
  end

  @doc """
  Streams the market events from the simulator.
  """
  @spec stream(t()) :: Enumerable.t(MarketEvent.t())
  def stream(%MarketSimulator{} = simulator) do
    %MarketSimulator{data: data, processors: processors} = simulator

    if map_size(data) == 0 do
      raise ArgumentError, "No data streams available in the simulator"
    end

    data_name = fetch_default_data_name(simulator)
    data = Map.fetch!(data, data_name)

    data
    |> Stream.map(&to_market_event(&1, data_name))
    |> add_processors(processors)
  end

  ## Private functions

  defp validate_stream!(stream) do
    if Enumerable.impl_for(stream) == nil do
      raise ArgumentError, "Invalid data feed provided, must implement Enumerable"
    end

    stream
  end

  defp fetch_default_data_name(%MarketSimulator{data: data}) do
    case Map.keys(data) do
      [default] -> default
      [] -> raise ArgumentError, "No data streams available in the simulator"
      _ -> raise ArgumentError, "Multiple data streams found, please use the :data option"
    end
  end

  defp to_market_event(tick_or_candle, name) do
    %MarketEvent{data: %{name => tick_or_candle}}
  end

  defp add_processors(stream, processors) do
    Enum.reduce(processors, stream, fn {data_name, {module, opts}}, acc_stream ->
      {:ok, initial_state} = module.init(opts)

      Stream.transform(acc_stream, initial_state, fn
        %MarketEvent{data: %{^data_name => _}} = event, state ->
          {:ok, new_event, new_state} =
            module.next(event, state)

          {[new_event], new_state}

        market_event, state ->
          {[market_event], state}
      end)
    end)
  end
end
