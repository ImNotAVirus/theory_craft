defmodule TheoryCraft.MarketSimulator do
  @moduledoc """
  Main orchestrator for building and running backtesting simulations using GenStage pipelines.

  The `MarketSimulator` provides a fluent API for constructing complex data processing pipelines
  with market data. It uses a builder pattern to configure the pipeline, then materializes it
  into a GenStage architecture when `stream/1` or `run/1` is called.

  ## Architecture

  The simulator uses a layered GenStage pipeline:
  - **DataFeedStage**: Producer that emits market data (ticks, candles)
  - **ProcessorStage**: Producer-consumer that transforms events (e.g., tick → candle)
  - **BroadcastStage**: Broadcasts events to multiple parallel processors
  - **AggregatorStage**: Synchronizes and merges outputs from parallel processors

  ## Usage

      # Build a pipeline with explicit names
      simulator =
        %MarketSimulator{}
        |> add_data_ticks_from_csv("ticks.csv", name: "XAUUSD")
        |> resample("m5", name: "XAUUSD_m5", data: "XAUUSD")
        |> resample("h1", name: "XAUUSD_h1", data: "XAUUSD")
        |> add_indicators_layer([
          {MyIndicator, name: "ind1", data: "XAUUSD_m5"},
          {MyIndicator, name: "ind2", data: "XAUUSD_h1"}
        ])

      # Stream events
      simulator
      |> stream()
      |> Enum.each(fn event ->
        # Process each market event
      end)

      # Or run to completion
      simulator |> run()

      # Simplified usage with default names
      %MarketSimulator{}
      |> add_data_ticks_from_csv("ticks.csv", name: "XAUUSD")
      |> resample("m5")   # data="XAUUSD", name="XAUUSD_m5" (automatic)
      |> resample("h1")   # data="XAUUSD", name="XAUUSD_h1" (automatic)
      |> stream()

  ## Layers

  The pipeline is built as a sequence of layers:
  - Each layer processes events from the previous layer
  - Single-processor layers use one `ProcessorStage`
  - Multi-processor layers use `BroadcastStage → N × ProcessorStage → AggregatorStage`

  ## Data Tracking

  The simulator maintains two separate collections:

  - **`data_feeds`**: Keyword list tracking only the initial data sources.
    Format: `[name: {data_feed_module, opts}]`
    Example: `[{"XAUUSD", {MemoryDataFeed, [from: feed]}}]`

  - **`data_streams`**: List of all available data stream names (feeds + processor outputs).
    Example: `["XAUUSD", "XAUUSD_m5", "XAUUSD_h1"]`

  This distinction allows processors to reference any available data stream, while
  only tracking the original data sources separately.

  ## Default Names

  To simplify pipeline construction, the simulator provides automatic name generation:

  ### Data Feed Names

  When `add_data/3` is called without a `:name` option, the name defaults to a numeric
  index (0 for the first feed, 1 for the second, etc.):

      add_data(simulator, MemoryDataFeed, from: feed)
      # name defaults to 0

  ### Processor Names

  When `resample/3` is called without `:data` or `:name` options:

  - `:data` defaults to the single data feed's name
  - `:name` defaults to `"{data}_{timeframe}"`

  Example:

      # With data feed named "XAUUSD"
      resample(simulator, "m5")
      # Equivalent to: resample(simulator, "m5", data: "XAUUSD", name: "XAUUSD_m5")

  This allows for concise pipeline construction when working with a single data feed:

      %MarketSimulator{}
      |> add_data(MemoryDataFeed, from: feed, name: "XAUUSD")
      |> resample("m1")   # Creates "XAUUSD_m1"
      |> resample("m5")   # Creates "XAUUSD_m5"
      |> resample("h1")   # Creates "XAUUSD_h1"

  ## Limitations

  - Currently supports one data feed at a time
  - Strategy execution not yet implemented (placeholders: `add_strategy`, `set_balance`, `set_commission`)
  """

  alias __MODULE__
  alias TheoryCraft.MarketEvent
  alias TheoryCraft.TimeFrame
  alias TheoryCraft.Processor
  alias TheoryCraft.Indicator
  alias TheoryCraft.Processors.TickToCandleProcessor
  alias TheoryCraft.DataFeeds.TicksCSVDataFeed
  alias TheoryCraft.Stages.DataFeedStage
  alias TheoryCraft.Stages.ProcessorStage
  alias TheoryCraft.Stages.BroadcastStage
  alias TheoryCraft.Stages.AggregatorStage
  alias TheoryCraft.Utils

  defstruct [
    # Data feeds as keyword list: [name: {module, opts}]
    data_feeds: [],
    # All data stream names (feeds + processor outputs)
    data_streams: [],
    # Building phase - store processor specs
    processor_layers: [],
    # Future features (placeholders)
    strategies: [],
    balance: nil,
    commission: nil
  ]

  @type strategy_spec :: {module(), Keyword.t()}

  @type t :: %MarketSimulator{
          data_feeds: Keyword.t({module(), Keyword.t()}),
          data_streams: [String.t() | non_neg_integer()],
          processor_layers: [[Processor.spec()]],
          strategies: [strategy_spec()],
          balance: number() | nil,
          commission: number() | nil
        }

  # stream =
  #   %MarketSimulator{}
  #   |> add_data_ticks_from_csv(filename, [name: "XAUUSD"] ++ opts)
  #   |> resample("m5", name: "XAUUSD_m5", data: "XAUUSD")
  #   |> resample("h1", name: "XAUUSD_h1", data: "XAUUSD")
  #   |> add_indicators_layer([
  #     {TheoryCraft.Indicators.Volume, name: "volume", data: "XAUUSD_m5"},
  #     {TheoryCraft.Indicators.SMA, period: 20, name: "short_term_m5", data: "XAUUSD_m5"},
  #     {TheoryCraft.Indicators.SMA, period: 100, name: "long_term_m5", data: "XAUUSD_m5"},
  #     {TheoryCraft.Indicators.ATR, period: 14, name: "atr_14", data: "XAUUSD_m5"},
  #     {TheoryCraft.Indicators.RSI, period: 14, name: "rsi_14", data: "XAUUSD_h1"},
  #   ], concurrency: 4)    
  #   |> add_indicator(TheoryCraft.Indicators.SMA, period: 14, name: "volume_sma_14", data: "volume")
  #   |> add_strategy(TheoryCraft.Strategies.MyStrategy)
  #   |> set_balance(100_000)
  #   |> set_commission(0.001)
  #   |> stream()

  # Enum.each(stream, fn event ->
  #   IO.inspect(event)
  # end)

  ## Public API

  @doc """
  Adds a data source to the market simulator.

  The `:name` option is optional. If not provided, the name defaults to the number
  of existing data feeds (0 for the first feed, 1 for the second, etc.).

  Currently, only one data feed is supported. An error is raised if you try to add
  a second data feed.

  ## Parameters

    - `simulator`: The market simulator.
    - `source`: Either:
      - A module implementing the `TheoryCraft.DataFeed` behaviour
      - An `Enumerable` (list, stream, etc.) containing `Tick` or `Candle` structs
    - `opts`: Options including:
      - `:name` - Optional name for this data stream (default: numeric index)
      - For DataFeed modules: other options are passed to the DataFeed module
      - For enumerables: `:name` is the only relevant option

  ## Examples

      # With DataFeed module and explicit name
      add_data(simulator, MemoryDataFeed, from: feed, name: "XAUUSD")

      # With DataFeed module and default name (will be 0)
      add_data(simulator, MemoryDataFeed, from: feed)

      # With enumerable (stream or list)
      ticks = [%Tick{...}, %Tick{...}]
      add_data(simulator, ticks, name: "XAUUSD")

      # With stream
      stream = Stream.map(ticks, & &1)
      add_data(simulator, stream, name: "XAUUSD")

  ## Notes

  The `:name` option is used as the data stream identifier and is NOT passed
  to the DataFeed module. All other options are passed through to the DataFeed.

  """
  @spec add_data(t(), module() | Enumerable.t(), Keyword.t()) :: t()
  def add_data(simulator, source, opts \\ [])

  def add_data(%MarketSimulator{} = simulator, data_feed_spec, opts)
      when is_atom(data_feed_spec) or is_tuple(data_feed_spec) do
    %MarketSimulator{data_feeds: data_feeds, data_streams: data_streams} = simulator

    if length(data_feeds) > 0 do
      raise ArgumentError, "Currently only one data feed is supported"
    end

    # Normalize the data feed spec
    {data_feed_module, data_feed_opts} = Utils.normalize_spec(data_feed_spec)

    # Default name = number of existing feeds
    name = Keyword.get_lazy(opts, :name, fn -> length(data_feeds) end)
    # Remove :name from opts and merge with data_feed_opts
    feed_opts = opts |> Keyword.delete(:name) |> Keyword.merge(data_feed_opts)

    %MarketSimulator{
      simulator
      | data_feeds: [{name, {data_feed_module, feed_opts}}],
        data_streams: [name | data_streams]
    }
  end

  def add_data(%MarketSimulator{} = simulator, enumerable, opts) do
    %MarketSimulator{data_feeds: data_feeds, data_streams: data_streams} = simulator

    if length(data_feeds) > 0 do
      raise ArgumentError, "Currently only one data feed is supported"
    end

    # Default name = number of existing feeds
    name = Keyword.get_lazy(opts, :name, fn -> length(data_feeds) end)

    %MarketSimulator{
      simulator
      | data_feeds: [{name, enumerable}],
        data_streams: [name | data_streams]
    }
  end

  @doc """
  Adds a data feed from a CSV file containing tick data.

  ## Parameters

    - `simulator`: The market simulator.
    - `file_path`: The path to the CSV file.
    - `opts`: Optional parameters for the data feed.

  """
  @spec add_data_ticks_from_csv(t(), String.t(), Keyword.t()) :: t()
  def add_data_ticks_from_csv(%MarketSimulator{} = simulator, file_path, opts \\ []) do
    data_feed_opts = [file: file_path] ++ opts
    add_data(simulator, TicksCSVDataFeed, data_feed_opts)
  end

  @doc """
  Resamples the data to a different timeframe.

  Creates a new processor layer with a single TickToCandleProcessor.

  ## Default Names

  - If `:data` is not provided, uses the name of the single data feed
  - If `:name` is not provided, generates it as `"{data}_{timeframe}"`

  ## Parameters

    - `simulator`: The market simulator.
    - `timeframe`: The new timeframe to resample the data to.
    - `opts`: Optional parameters:
      - `:data` - Source data name (default: data feed name)
      - `:name` - Output data name (default: `"{data}_{timeframe}"`)
      - Other processor options

  ## Examples

      # With explicit data and name
      resample(simulator, "m5", data: "XAUUSD", name: "XAUUSD_m5")

      # With default names (if data feed is named "XAUUSD")
      resample(simulator, "m5")  # data="XAUUSD", name="XAUUSD_m5"

  """
  @spec resample(t(), String.t(), Keyword.t()) :: t()
  def resample(%MarketSimulator{} = simulator, timeframe, opts \\ []) do
    %MarketSimulator{
      data_streams: data_streams,
      processor_layers: processor_layers
    } = simulator

    if not TimeFrame.valid?(timeframe) do
      raise ArgumentError, "Invalid timeframe #{inspect(timeframe)}"
    end

    # Deduce :data if not provided (from data feeds)
    data_name =
      Keyword.get_lazy(opts, :data, fn ->
        fetch_default_data_name(simulator)
      end)

    # Validate that data_name exists
    if data_name not in data_streams do
      raise ArgumentError, "Data stream #{inspect(data_name)} not found"
    end

    # Generate :name if not provided
    output_name =
      Keyword.get_lazy(opts, :name, fn ->
        "#{data_name}_#{timeframe}"
      end)

    # Build processor options
    processor_opts =
      opts
      |> Keyword.put(:timeframe, timeframe)
      |> Keyword.put(:data, data_name)
      |> Keyword.put(:name, output_name)

    processor_spec = {TickToCandleProcessor, processor_opts}

    # Add new layer with single processor and track new data stream
    %MarketSimulator{
      simulator
      | processor_layers: processor_layers ++ [[processor_spec]],
        data_streams: [output_name | data_streams]
    }
  end

  @doc """
  Adds a layer with multiple processors running in parallel.

  This creates a layer where multiple processors (indicators) process events
  simultaneously. Events are broadcast to all processors, and their outputs
  are synchronized and merged by an AggregatorStage.

  ## Default Names

  - If `:data` is not provided in processor opts, uses the name of the single data feed

  ## Parameters

    - `simulator`: The market simulator.
    - `processor_specs`: List of `{module, opts}` tuples for each processor.
    - `opts`: Optional parameters (e.g., `:concurrency` - currently unused).

  ## Examples

      # With explicit data
      simulator
      |> add_indicators_layer([
        {TheoryCraft.Indicators.Volume, name: "volume", data: "XAUUSD_m5"},
        {TheoryCraft.Indicators.SMA, period: 20, name: "sma_20", data: "XAUUSD_m5"}
      ])

      # With default data (if single data feed)
      simulator
      |> add_indicators_layer([
        {TheoryCraft.Indicators.Volume, name: "volume"},
        {TheoryCraft.Indicators.SMA, period: 20, name: "sma_20"}
      ])

  """
  @spec add_indicators_layer(t(), [Indicator.spec()], Keyword.t()) :: t()
  def add_indicators_layer(%MarketSimulator{} = simulator, indicator_specs, _opts \\ [])
      when is_list(indicator_specs) do
    %MarketSimulator{data_streams: data_streams, processor_layers: processor_layers} = simulator

    if indicator_specs == [] do
      raise ArgumentError, "indicator_specs cannot be empty"
    end

    # Add default :data to each indicator spec if not provided
    enhanced_specs =
      Enum.map(indicator_specs, fn indicator_spec ->
        {module, indicator_opts} = Utils.normalize_spec(indicator_spec)

        data_name =
          Keyword.get_lazy(indicator_opts, :data, fn ->
            fetch_default_data_name(simulator)
          end)

        # Validate that data source exists
        if data_name not in data_streams do
          raise ArgumentError, "Data stream #{inspect(data_name)} not found"
        end

        # Add :data to opts if not present
        enhanced_opts = Keyword.put_new(indicator_opts, :data, data_name)
        {module, enhanced_opts}
      end)

    # Extract all output names
    new_data_names =
      for {_module, indicator_opts} <- enhanced_specs do
        Keyword.fetch!(indicator_opts, :name)
      end

    # Add new layer with multiple processors and track new data streams
    %MarketSimulator{
      simulator
      | processor_layers: processor_layers ++ [enhanced_specs],
        data_streams: new_data_names ++ data_streams
    }
  end

  @doc """
  Adds a single indicator/processor as a new layer.

  This is a convenience function that creates a layer with a single processor.
  Equivalent to `add_indicators_layer(simulator, [{module, opts}])`.

  ## Default Names

  - If `:data` is not provided, uses the name of the single data feed

  ## Parameters

    - `simulator`: The market simulator.
    - `processor_module`: The processor/indicator module.
    - `opts`: Options for the processor.

  ## Examples

      # With explicit data
      simulator
      |> add_indicator(TheoryCraft.Indicators.SMA, period: 14, name: "sma_14", data: "volume")

      # With default data (if single data feed)
      simulator
      |> add_indicator(TheoryCraft.Indicators.SMA, period: 14, name: "sma_14")

  """
  @spec add_indicator(t(), module(), Keyword.t()) :: t()
  def add_indicator(%MarketSimulator{} = simulator, processor_module, opts) do
    %MarketSimulator{data_streams: data_streams, processor_layers: processor_layers} = simulator

    # Deduce :data if not provided
    data_name =
      Keyword.get_lazy(opts, :data, fn ->
        fetch_default_data_name(simulator)
      end)

    # Validate data source
    if data_name not in data_streams do
      raise ArgumentError, "Data stream #{inspect(data_name)} not found"
    end

    output_name = Keyword.fetch!(opts, :name)

    # Add :data to opts if not present
    enhanced_opts = Keyword.put_new(opts, :data, data_name)
    processor_spec = {processor_module, enhanced_opts}

    # Add new layer with single processor and track new data stream
    %MarketSimulator{
      simulator
      | processor_layers: processor_layers ++ [[processor_spec]],
        data_streams: [output_name | data_streams]
    }
  end

  @doc """
  Adds a trading strategy to the simulator.

  Multiple strategies can be added to the simulator. Each strategy can have its own
  configuration options.

  **Note**: Strategy execution is not yet implemented.

  ## Parameters

    - `simulator`: The market simulator.
    - `strategy_module`: The strategy module to use.
    - `opts`: Optional parameters for the strategy (default: `[]`).

  ## Examples

      # Add strategy without options
      add_strategy(simulator, MyStrategy)

      # Add strategy with options
      add_strategy(simulator, MyStrategy, risk_level: :high, max_positions: 5)

      # Add multiple strategies
      simulator
      |> add_strategy(Strategy1, param1: 100)
      |> add_strategy(Strategy2, param2: 200)

  """
  @spec add_strategy(t(), module() | {module(), Keyword.t()}, Keyword.t()) :: t()
  def add_strategy(%MarketSimulator{} = simulator, strategy_spec, opts \\ [])
      when is_atom(strategy_spec) or is_tuple(strategy_spec) do
    %MarketSimulator{strategies: strategies} = simulator
    # When opts is provided, merge them with the spec opts
    {strategy_module, spec_opts} = Utils.normalize_spec(strategy_spec)
    strategy_opts = Keyword.merge(spec_opts, opts)

    %MarketSimulator{simulator | strategies: strategies ++ [{strategy_module, strategy_opts}]}
  end

  @doc """
  Sets the initial balance for backtesting.

  **Note**: Balance tracking is not yet implemented.

  ## Parameters

    - `simulator`: The market simulator.
    - `balance`: The initial balance amount.

  """
  @spec set_balance(t(), number()) :: t()
  def set_balance(%MarketSimulator{} = simulator, balance) when is_number(balance) do
    %MarketSimulator{simulator | balance: balance}
  end

  @doc """
  Sets the commission rate for trades.

  **Note**: Commission calculation is not yet implemented.

  ## Parameters

    - `simulator`: The market simulator.
    - `commission`: The commission rate (e.g., 0.001 for 0.1%).

  """
  @spec set_commission(t(), number()) :: t()
  def set_commission(%MarketSimulator{} = simulator, commission) when is_number(commission) do
    %MarketSimulator{simulator | commission: commission}
  end

  @doc """
  Materializes the simulator into a GenStage pipeline and returns an Enumerable stream.

  This function:
  1. Starts a DataFeedStage producer from the data feed spec
  2. For each processor layer:
     - Single processor: starts a ProcessorStage
     - Multiple processors: starts BroadcastDispatcher → N ProcessorStages → AggregatorStage
  3. Returns `GenStage.stream/1` of the final stage

  ## Parameters

    - `simulator`: The market simulator.
    - `opts`: Optional parameters (currently unused).

  ## Returns

  An Enumerable that yields MarketEvents.

  ## Examples

      simulator
      |> MarketSimulator.stream()
      |> Enum.take(100)

  """
  @spec stream(t(), Keyword.t()) :: Enumerable.t(MarketEvent.t())
  def stream(%MarketSimulator{} = simulator, _opts \\ []) do
    %MarketSimulator{data_feeds: data_feeds} = simulator

    if data_feeds == [] do
      raise ArgumentError,
            "No data feed configured. Use add_data/3 or add_data_ticks_from_csv/3 first."
    end

    # Materialize the GenStage pipeline
    {data_feed_pid, final_stage_pid} = materialize_pipeline(simulator)

    # Return GenStage stream with producers specified
    GenStage.stream([{final_stage_pid, cancel: :transient}], producers: [data_feed_pid])
  end

  @doc """
  Runs the simulator pipeline to completion.

  Equivalent to calling `stream/1` and consuming all events with `Enum.to_list/1`,
  but discards the results. Useful for backtesting where you only care about
  side effects (e.g., strategy execution, logging).

  ## Parameters

    - `simulator`: The market simulator.
    - `opts`: Optional parameters passed to `stream/1`.

  ## Returns

  `:ok`

  ## Examples

      simulator
      |> MarketSimulator.run()

  """
  @spec run(t(), Keyword.t()) :: :ok
  def run(%MarketSimulator{} = simulator, opts \\ []) do
    _events = simulator |> stream(opts) |> Enum.to_list()
    :ok
  end

  ## Private functions

  # Fetches the default data name from data feeds
  # Returns the name of the single data feed, or raises if none or multiple
  defp fetch_default_data_name(%MarketSimulator{data_feeds: data_feeds}) do
    case data_feeds do
      [{name, _feed_spec}] ->
        name

      [] ->
        raise ArgumentError, "No data feeds available"

      _ ->
        raise ArgumentError,
              "Multiple data feeds found, please specify :data option explicitly"
    end
  end

  # Materializes the GenStage pipeline from specs
  defp materialize_pipeline(%MarketSimulator{} = simulator) do
    %MarketSimulator{data_feeds: data_feeds, processor_layers: processor_layers} = simulator

    # Extract the single data feed source (can be {module, opts} or enumerable)
    [{data_name, source}] = data_feeds

    # Start DataFeedStage producer with demand: :accumulate
    {:ok, data_feed_pid} = DataFeedStage.start_link(source, name: data_name)

    # Build pipeline left to right
    final_stage_pid =
      Enum.reduce(processor_layers, data_feed_pid, fn layer, upstream_pid ->
        materialize_layer(layer, upstream_pid)
      end)

    {data_feed_pid, final_stage_pid}
  end

  # Materialize a single processor layer
  defp materialize_layer([processor_spec], upstream_pid) do
    # Single processor - start ProcessorStage with subscription
    {:ok, processor_pid} =
      ProcessorStage.start_link(
        processor_spec,
        subscribe_to: [{upstream_pid, cancel: :transient}]
      )

    processor_pid
  end

  defp materialize_layer(processor_specs, upstream_pid)
       when is_list(processor_specs) and length(processor_specs) > 1 do
    # Multiple processors - need broadcast → N processors → aggregator

    # 1. Start BroadcastStage
    {:ok, broadcast_pid} =
      BroadcastStage.start_link(subscribe_to: [{upstream_pid, cancel: :transient}])

    # 2. Start N ProcessorStages first
    processor_pids =
      Enum.map(processor_specs, fn processor_spec ->
        {:ok, processor_pid} =
          ProcessorStage.start_link(
            processor_spec,
            subscribe_to: [{broadcast_pid, cancel: :transient}]
          )

        processor_pid
      end)

    # 3. Start AggregatorStage with all ProcessorStages in subscribe_to
    subscriptions = Enum.map(processor_pids, fn pid -> {pid, cancel: :transient} end)

    {:ok, aggregator_pid} =
      AggregatorStage.start_link(
        producer_count: length(processor_specs),
        subscribe_to: subscriptions
      )

    # Return aggregator as the final stage of this layer
    aggregator_pid
  end
end
