defmodule TheoryCraft.IndicatorValue do
  @moduledoc """
  A wrapper for indicator values that enables lazy temporal context lookup.

  When indicators calculate values based on bars, ticks, or other indicators, they need
  access to temporal context like bar time, new_bar?, and new_session? flags. However,
  storing this information directly in the indicator value would create unnecessary coupling
  and memory overhead.

  IndicatorValue solves this by storing a reference to the source data name, enabling
  lazy lookup of temporal context from the MarketEvent data map when needed.

  ## Architecture

  An IndicatorValue contains:
  - `value` - The actual indicator calculation result (can be any type)
  - `data_name` - The name of the data source this indicator was calculated from

  When you need temporal context (e.g., bar_time, new_bar?), you pass the IndicatorValue
  and the event data map to the appropriate helper function, which:
  1. Looks up the source data using `data_name`
  2. If the source is a Bar/Tick, extracts the field directly
  3. If the source is another IndicatorValue, recursively looks up its source
  4. Returns the default value if not found

  ## Performance

  This lazy lookup approach adds minimal overhead:
  - Lookups are O(1) map access
  - Recursion depth is typically 1-3 levels (indicator on bar, or indicator on indicator on bar)
  - No memory overhead from storing redundant temporal data

  ## Examples

      # Create an indicator value
      value = %IndicatorValue{
        value: 45.2,
        data_name: "eurusd_m5"
      }

      # Lazy lookup of bar time from event data
      event_data = %{
        "eurusd_m5" => %Bar{time: ~U[2024-01-01 10:00:00Z], close: 1.23, new_bar?: true}
      }

      IndicatorValue.bar_time(value, event_data)
      # => ~U[2024-01-01 10:00:00Z]

      IndicatorValue.new_bar?(value, event_data)
      # => true

      # Nested indicators (indicator on indicator)
      sma_value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      ema_on_sma = %IndicatorValue{value: 45.1, data_name: "sma20"}

      event_data = %{
        "eurusd_m5" => %Bar{time: ~U[2024-01-01 10:00:00Z], new_bar?: true},
        "sma20" => sma_value
      }

      # Recursively looks up through sma20 -> eurusd_m5
      IndicatorValue.bar_time(ema_on_sma, event_data)
      # => ~U[2024-01-01 10:00:00Z]

  """

  alias __MODULE__
  alias TheoryCraft.{Bar, Tick}

  defstruct [:value, :data_name]

  @type t :: %IndicatorValue{
          value: any(),
          data_name: String.t()
        }

  ## Public API

  @doc """
  Extracts the bar time from the indicator's source data.

  This function performs a lazy lookup by following the data_name reference
  to find the source data in the event_data map. If the source is another
  IndicatorValue, it recursively follows the chain until it finds a Bar/Tick
  with a time field.

  ## Parameters

    - `indicator_value` - The IndicatorValue struct
    - `event_data` - The MarketEvent data map
    - `default` - Default value if time cannot be found (default: nil)

  ## Returns

    - `DateTime.t()` if the source has a time field
    - `default` if the source cannot be found or has no time

  ## Examples

      iex> alias TheoryCraft.Bar
      iex> value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      iex> event_data = %{"eurusd_m5" => %Bar{time: ~U[2024-01-01 10:00:00Z], close: 1.23}}
      iex> IndicatorValue.bar_time(value, event_data)
      ~U[2024-01-01 10:00:00Z]

      iex> alias TheoryCraft.Bar
      iex> value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      iex> event_data = %{"eurusd_m5" => %Bar{time: ~U[2024-01-01 10:00:00Z], close: 1.23}}
      iex> IndicatorValue.bar_time(value, event_data, ~U[2024-01-01 00:00:00Z])
      ~U[2024-01-01 10:00:00Z]

      iex> value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      iex> IndicatorValue.bar_time(value, %{}, ~U[2024-01-01 00:00:00Z])
      ~U[2024-01-01 00:00:00Z]

  """
  @spec bar_time(t(), map(), DateTime.t() | nil) :: DateTime.t() | nil
  def bar_time(%IndicatorValue{data_name: data_name}, event_data, default \\ nil) do
    case event_data do
      %{^data_name => %{time: time}} ->
        time

      %{^data_name => %IndicatorValue{} = ind} ->
        bar_time(ind, event_data, default)

      %{} ->
        default
    end
  end

  @doc """
  Extracts the new_bar? flag from the indicator's source data.

  This function performs a lazy lookup by following the data_name reference
  to find the source data in the event_data map. If the source is another
  IndicatorValue, it recursively follows the chain until it finds a Bar or Tick.

  ## Behavior

    - If source is a Bar with `new_bar?` field: returns the flag value
    - If source is a Tick: returns `true` (each tick is a new bar)
    - If source is another IndicatorValue: recursively follows the chain
    - Otherwise: raises an error

  ## Parameters

    - `indicator_value` - The IndicatorValue struct
    - `event_data` - The MarketEvent data map

  ## Returns

    - `boolean()` - The new_bar? flag value

  ## Raises

    - If `data_name` is not found in event_data
    - If the source data is not a Bar, Tick, or IndicatorValue

  ## Examples

      iex> alias TheoryCraft.Bar
      iex> value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      iex> event_data = %{"eurusd_m5" => %Bar{close: 1.23, new_bar?: true}}
      iex> IndicatorValue.new_bar?(value, event_data)
      true

      iex> alias TheoryCraft.Tick
      iex> value = %IndicatorValue{value: 1.23, data_name: "eurusd_ticks"}
      iex> event_data = %{"eurusd_ticks" => %Tick{time: ~U[2024-01-01 10:00:00Z], ask: 1.23, bid: 1.22, ask_volume: 100.0, bid_volume: 100.0}}
      iex> IndicatorValue.new_bar?(value, event_data)
      true

  """
  @spec new_bar?(t(), map()) :: boolean()
  def new_bar?(%IndicatorValue{data_name: data_name}, event_data) do
    case event_data do
      %{^data_name => %Bar{new_bar?: flag}} when is_boolean(flag) ->
        flag

      %{^data_name => %Tick{}} ->
        true

      %{^data_name => %IndicatorValue{} = ind} ->
        new_bar?(ind, event_data)

      %{^data_name => _value} ->
        raise "IndicatorValue source #{inspect(data_name)} is not a Bar, Tick, or IndicatorValue"

      %{} ->
        raise "IndicatorValue source #{inspect(data_name)} not found in event data"
    end
  end

  @doc """
  Extracts the new_market? flag from the indicator's source data.

  This function performs a lazy lookup by following the data_name reference
  to find the source data in the event_data map. If the source is another
  IndicatorValue, it recursively follows the chain until it finds a Bar or Tick.

  ## Behavior

    - If source is a Bar with `new_market?` field: returns the flag value
    - If source is a Tick: returns `false` (ticks don't have market boundaries)
    - If source is another IndicatorValue: recursively follows the chain
    - Otherwise: raises an error

  ## Parameters

    - `indicator_value` - The IndicatorValue struct
    - `event_data` - The MarketEvent data map

  ## Returns

    - `boolean()` - The new_market? flag value

  ## Raises

    - If `data_name` is not found in event_data
    - If the source data is not a Bar, Tick, or IndicatorValue

  ## Examples

      iex> alias TheoryCraft.Bar
      iex> value = %IndicatorValue{value: 45.0, data_name: "eurusd_m5"}
      iex> event_data = %{"eurusd_m5" => %Bar{close: 1.23, new_market?: false}}
      iex> IndicatorValue.new_market?(value, event_data)
      false

      iex> alias TheoryCraft.Tick
      iex> value = %IndicatorValue{value: 1.23, data_name: "eurusd_ticks"}
      iex> event_data = %{"eurusd_ticks" => %Tick{time: ~U[2024-01-01 10:00:00Z], ask: 1.23, bid: 1.22, ask_volume: 100.0, bid_volume: 100.0}}
      iex> IndicatorValue.new_market?(value, event_data)
      false

  """
  @spec new_market?(t(), map()) :: boolean()
  def new_market?(%IndicatorValue{data_name: data_name}, event_data) do
    case event_data do
      %{^data_name => %Bar{new_market?: flag}} when is_boolean(flag) ->
        flag

      %{^data_name => %Tick{}} ->
        false

      %{^data_name => %IndicatorValue{} = ind} ->
        new_market?(ind, event_data)

      %{^data_name => _value} ->
        raise "IndicatorValue source #{inspect(data_name)} is not a Bar, Tick, or IndicatorValue"

      %{} ->
        raise "IndicatorValue source #{inspect(data_name)} not found in event data"
    end
  end
end
