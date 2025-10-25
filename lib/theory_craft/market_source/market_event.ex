defmodule TheoryCraft.MarketSource.MarketEvent do
  @moduledoc """
  Represents a market event flowing through the processing pipeline.

  A MarketEvent is a wrapper that carries market data (ticks, bars, indicator values)
  through the pipeline, allowing multiple data streams to be processed and
  combined in a single event flow.

  ## Structure

  - `time` - The event timestamp (typically the tick time or current data point time)
  - `source` - The name of the originating data source (e.g., "eurusd", "xauusd")
  - `data` - A map of data stream names to their values (bars, ticks, indicators)

  ## Event Time vs Bar Time

  The `time` field represents the actual event time (e.g., when a tick occurred),
  while bars and other data in the `data` map may have their own aligned times.
  For example:

  - Event time: ~U[2024-01-01 10:02:34Z] (tick time)
  - Bar time: ~U[2024-01-01 10:00:00Z] (5-minute bar aligned to 10:00)

  ## Examples

      # Event with a single tick
      %MarketEvent{
        time: ~U[2024-01-01 10:02:34Z],
        source: "eurusd",
        data: %{
          "eurusd" => %Tick{time: ~U[2024-01-01 10:02:34Z], ask: 1.23, bid: 1.22}
        }
      }

      # Event with resampled bar and indicators
      %MarketEvent{
        time: ~U[2024-01-01 10:02:34Z],
        source: "eurusd",
        data: %{
          "eurusd" => %Tick{...},
          "eurusd_m5" => %Bar{time: ~U[2024-01-01 10:00:00Z], close: 1.23, new_bar?: false},
          "sma20" => %IndicatorValue{value: 1.225, data_name: "eurusd_m5"}
        }
      }

  """

  alias __MODULE__
  alias TheoryCraft.MarketSource.{Bar, Tick}
  alias TheoryCraft.MarketSource.IndicatorValue

  defstruct [:time, :source, data: %{}]

  @type t :: %MarketEvent{
          time: DateTime.t(),
          source: String.t(),
          data: map()
        }

  ## Public API

  @doc """
  Extracts a value from the event's data map.

  Handles three cases:
  - If the data is a Bar/struct and `source` is provided, extracts the field specified by `source`
  - If the data is an IndicatorValue, extracts the underlying value
  - If the data is a raw value (float/nil), returns it directly

  ## Parameters

    - `event` - The MarketEvent struct
    - `data_name` - The key to extract from event.data
    - `source` - The field to extract from the Bar/struct (optional, e.g., `:close`, `:high`)

  ## Returns

    - The extracted value (any type)

  ## Raises

    - If `data_name` is not found in `event.data`
    - If `source` is provided but not found in the Bar/struct

  ## Examples

      iex> alias TheoryCraft.MarketSource.Bar
      iex> alias TheoryCraft.MarketSource.IndicatorValue
      iex> event = %MarketEvent{data: %{"eurusd_m5" => %Bar{close: 1.23, high: 1.25}}}
      iex> MarketEvent.extract_value(event, "eurusd_m5", :close)
      1.23

      iex> alias TheoryCraft.MarketSource.IndicatorValue
      iex> event = %MarketEvent{data: %{"sma20" => %IndicatorValue{value: 1.25, data_name: "eurusd_m5"}}}
      iex> MarketEvent.extract_value(event, "sma20", nil)
      1.25

      iex> event = %MarketEvent{data: %{"raw_value" => 42.0}}
      iex> MarketEvent.extract_value(event, "raw_value", nil)
      42.0

  """
  @spec extract_value(t(), String.t(), atom() | nil) :: any()
  def extract_value(%MarketEvent{data: event_data}, data_name, source \\ nil) do
    case event_data do
      %{^data_name => %IndicatorValue{value: value}} ->
        value

      %{^data_name => value} when is_nil(source) ->
        value

      %{^data_name => %{^source => value}} ->
        value

      %{^data_name => %{}} when not is_nil(source) ->
        raise "source #{inspect(source)} not found in data"

      %{} ->
        raise "data_name #{inspect(data_name)} not found in event"
    end
  end

  @doc """
  Extracts the `new_bar?` flag from the event's data map.

  ## Parameters

    - `event` - The MarketEvent struct
    - `data_name` - The key to extract from event.data

  ## Returns

    - `true` or `false`

  ## Behavior

    - If data is a Bar with `new_bar?` field: returns the flag value
    - If data is a Tick: returns `true` (each tick is a new bar)
    - If data is an IndicatorValue: uses lazy lookup to find the source bar/tick
    - Otherwise: raises an error

  ## Raises

    - If `data_name` is not found in event data
    - If data is not a Bar, Tick, or IndicatorValue

  ## Examples

      iex> alias TheoryCraft.MarketSource.Bar
      iex> event = %MarketEvent{data: %{"eurusd_m5" => %Bar{close: 1.23, new_bar?: false}}}
      iex> MarketEvent.new_bar?(event, "eurusd_m5")
      false

      iex> alias TheoryCraft.MarketSource.Tick
      iex> event = %MarketEvent{data: %{"eurusd_ticks" => %Tick{time: ~U[2024-01-01 10:00:00Z], ask: 1.23, bid: 1.22, ask_volume: 100.0, bid_volume: 100.0}}}
      iex> MarketEvent.new_bar?(event, "eurusd_ticks")
      true

  """
  @spec new_bar?(t(), String.t()) :: boolean()
  def new_bar?(%MarketEvent{data: event_data}, data_name) do
    case event_data do
      %{^data_name => %Bar{new_bar?: new_bar?}} when is_boolean(new_bar?) ->
        new_bar?

      %{^data_name => %Tick{}} ->
        true

      %{^data_name => %IndicatorValue{} = ind} ->
        IndicatorValue.new_bar?(ind, event_data)

      %{^data_name => _value} ->
        raise "data #{inspect(data_name)} is not a Bar, Tick, or IndicatorValue"

      %{} ->
        raise "data_name #{inspect(data_name)} not found in event"
    end
  end

  @doc """
  Extracts the `new_market?` flag from the event's data map.

  ## Parameters

    - `event` - The MarketEvent struct
    - `data_name` - The key to extract from event.data

  ## Returns

    - `true` or `false`

  ## Behavior

    - If data is a Bar with `new_market?` field: returns the flag value
    - If data is a Tick: returns `false` (ticks don't have market boundaries)
    - If data is an IndicatorValue: uses lazy lookup to find the source bar/tick
    - Otherwise: raises an error

  ## Raises

    - If `data_name` is not found in event data
    - If data is not a Bar, Tick, or IndicatorValue

  ## Examples

      iex> alias TheoryCraft.MarketSource.Bar
      iex> event = %MarketEvent{data: %{"eurusd_m5" => %Bar{close: 1.23, new_market?: true}}}
      iex> MarketEvent.new_market?(event, "eurusd_m5")
      true

      iex> alias TheoryCraft.MarketSource.Tick
      iex> event = %MarketEvent{data: %{"eurusd_ticks" => %Tick{time: ~U[2024-01-01 10:00:00Z], ask: 1.23, bid: 1.22, ask_volume: 100.0, bid_volume: 100.0}}}
      iex> MarketEvent.new_market?(event, "eurusd_ticks")
      false

  """
  @spec new_market?(t(), String.t()) :: boolean()
  def new_market?(%MarketEvent{data: event_data}, data_name) do
    case event_data do
      %{^data_name => %Bar{new_market?: new_market?}} when is_boolean(new_market?) ->
        new_market?

      %{^data_name => %Tick{}} ->
        false

      %{^data_name => %IndicatorValue{} = ind} ->
        IndicatorValue.new_market?(ind, event_data)

      %{^data_name => _value} ->
        raise "data #{inspect(data_name)} is not a Bar, Tick, or IndicatorValue"

      %{} ->
        raise "data_name #{inspect(data_name)} not found in event"
    end
  end
end
