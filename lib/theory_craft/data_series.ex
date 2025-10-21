defmodule TheoryCraft.DataSeries do
  @moduledoc """
  A read-optimized circular buffer for storing time series data.

  `DataSeries` is a specialized data structure designed for efficiently storing and
  accessing historical data in reverse chronological order (newest first). It implements
  the `Access` and `Enumerable` protocols, allowing bracket notation, Kernel functions
  like `get_in/2`, `update_in/3`, and `get_and_update_in/3`, as well as all `Enum`
  functions like `Enum.map/2`, `Enum.filter/2`, etc.

  ## Key Features

  - **Reverse chronological order**: Index 0 is the most recent value, index 1 is the
    second most recent, etc.
  - **Circular buffer**: When `max_size` is reached, the oldest value is automatically
    dropped when adding new values.
  - **Read-optimized**: Fast access to recent values using list head operations.
  - **Access protocol**: Supports bracket syntax and Kernel helper functions.
  - **Enumerable protocol**: Supports all `Enum` functions for enumeration and transformation.

  ## Use Cases

  DataSeries is ideal for:
  - Storing historical bars/bars for technical indicators
  - Maintaining lookback windows for calculations (e.g., moving averages)
  - Time series data where recent values are accessed more frequently

  ## Circular Buffer Behavior

  When a `max_size` is specified and the buffer is full, adding a new value will:
  1. Add the new value at the head (index 0)
  2. Drop the oldest value from the tail
  3. Keep the size constant at `max_size`

  ## Access Protocol

  DataSeries implements the `Access` behaviour with the following restrictions:

  - `fetch/2`: Returns `{:ok, value}` for valid indices, `:error` otherwise
  - `get_and_update/3`: Allows updating values, but raises if the function returns `:pop`
  - `pop/2`: Always raises an error (popping is not supported)

  ## Enumerable Protocol

  DataSeries implements the `Enumerable` protocol, allowing you to use all `Enum` functions:

  - `Enum.map/2`: Transform each value
  - `Enum.filter/2`: Filter values based on a predicate
  - `Enum.reduce/3`: Reduce values to a single value
  - `Enum.count/1`: Count the number of values (equivalent to `DataSeries.size/1`)
  - And all other `Enum` functions

  Note: The enumeration order is the same as the internal list order (newest to oldest).

  ## Performance Characteristics

  - **Add**: O(1) for infinite size, O(n) when max_size is reached (due to tail drop)
  - **Access by index**: O(n) where n is the index (list traversal)
  - **Last**: O(1) (head access)
  - **Size**: O(1)

  ## Examples

      # Create an empty DataSeries with infinite size
      iex> series = DataSeries.new()
      iex> DataSeries.size(series)
      0
      iex> series.max_size
      :infinity

      # Create a DataSeries with a maximum size of 5
      iex> series = DataSeries.new(max_size: 5)
      iex> DataSeries.size(series)
      0
      iex> series.max_size
      5

      # Add values (newest values go to index 0)
      iex> series = DataSeries.new()
      iex> series = DataSeries.add(series, 10)
      iex> series = DataSeries.add(series, 20)
      iex> series = DataSeries.add(series, 30)
      iex> series[0]  # Most recent
      30
      iex> series[1]
      20
      iex> series[2]  # Oldest
      10

      # Circular buffer behavior
      iex> series = DataSeries.new(max_size: 3)
      iex> series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)
      iex> DataSeries.size(series)
      3
      iex> series = DataSeries.add(series, 4)  # Drops 1
      iex> series[0]
      4
      iex> series[2]
      2
      iex> series[3]  # Out of bounds
      nil

      # Using get_in/2
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> get_in(series, [0])
      20
      iex> get_in(series, [1])
      10

      # Using update_in/3
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> new_series = update_in(series, [0], fn val -> val * 2 end)
      iex> new_series[0]
      40
      iex> series[0]  # Original unchanged
      20

      # Using get_and_update_in/3
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> {old_value, new_series} = get_and_update_in(series, [0], fn val -> {val, val + 5} end)
      iex> old_value
      20
      iex> new_series[0]
      25

      # Get the most recent value
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> DataSeries.last(series)
      20

      # Get the current size
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> DataSeries.size(series)
      2

      # Using Enum.map/2
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> Enum.map(series, fn x -> x * 2 end)
      [60, 40, 20]

      # Using Enum.filter/2
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> Enum.filter(series, fn x -> x > 15 end)
      [30, 20]

      # Using Enum.reduce/3
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> Enum.reduce(series, 0, fn x, acc -> x + acc end)
      60

  """

  alias __MODULE__

  @behaviour Access

  @enforce_keys [:data, :size, :max_size]
  defstruct @enforce_keys

  @type t :: %DataSeries{
          data: list(),
          size: non_neg_integer(),
          max_size: pos_integer() | :infinity
        }

  @type t(data_type) :: %DataSeries{
          data: [data_type],
          size: non_neg_integer(),
          max_size: pos_integer() | :infinity
        }

  ## Public API

  @doc """
  Creates a new empty DataSeries.

  ## Options

    - `:max_size` - Maximum number of values to store. When this limit is reached,
      the oldest value is dropped when adding new values. Defaults to `:infinity`.

  ## Returns

    - A new `DataSeries` struct with empty data and size 0

  ## Examples

      # Create an infinite DataSeries
      iex> series = DataSeries.new()
      iex> DataSeries.size(series)
      0
      iex> series.max_size
      :infinity

      # Create a DataSeries with maximum 10 values
      iex> series = DataSeries.new(max_size: 10)
      iex> series.max_size
      10

      # Create a DataSeries with maximum 5 values
      iex> series = DataSeries.new(max_size: 5)
      iex> series.max_size
      5

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %DataSeries{
      data: [],
      size: 0,
      max_size: Keyword.get(opts, :max_size, :infinity)
    }
  end

  @doc """
  Returns the most recent value in the DataSeries.

  This is equivalent to accessing index 0, but more convenient when you only
  need the latest value.

  ## Parameters

    - `series` - The DataSeries to get the last value from

  ## Returns

    - The most recent value (head of the internal list)
    - `nil` if the DataSeries is empty

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> DataSeries.last(series)
      20

      iex> series = DataSeries.new()
      iex> DataSeries.last(series)
      nil

      iex> series = DataSeries.new() |> DataSeries.add(42)
      iex> DataSeries.last(series)
      42

  """
  @spec last(t()) :: any()
  def last(%DataSeries{} = series) do
    case series do
      %DataSeries{data: [last | _]} -> last
      %DataSeries{data: []} -> nil
    end
  end

  @doc """
  Returns the current number of values in the DataSeries.

  ## Parameters

    - `series` - The DataSeries to get the size of

  ## Returns

    - A non-negative integer representing the current number of stored values

  ## Examples

      iex> series = DataSeries.new()
      iex> DataSeries.size(series)
      0

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> DataSeries.size(series)
      2

      iex> series = DataSeries.new(max_size: 3)
      iex> series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)
      iex> DataSeries.size(series)
      3

      # Size stays constant when max_size is reached
      iex> series = DataSeries.new(max_size: 3)
      iex> series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3) |> DataSeries.add(4)
      iex> DataSeries.size(series)
      3

  """
  @spec size(t()) :: non_neg_integer()
  def size(%DataSeries{size: size}) do
    size
  end

  @doc """
  Returns the value at the given index.

  Supports negative indices like `Enum.at/2`: -1 is the oldest value, -2 is the
  second oldest, etc.

  ## Parameters

    - `series` - The DataSeries to get the value from
    - `index` - Zero-based index where:
      - Positive: 0 is newest, 1 is second newest, etc.
      - Negative: -1 is oldest, -2 is second oldest, etc.

  ## Returns

    - The value at the index if valid
    - `nil` if the index is out of bounds

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> DataSeries.at(series, 0)
      30
      iex> DataSeries.at(series, 1)
      20
      iex> DataSeries.at(series, -1)
      10

      iex> series = DataSeries.new() |> DataSeries.add(42)
      iex> DataSeries.at(series, 0)
      42
      iex> DataSeries.at(series, 1)
      nil

  """
  @spec at(t(), integer()) :: any() | nil
  def at(%DataSeries{data: data}, index) do
    Enum.at(data, index)
  end

  @doc """
  Replaces the value at the given index.

  This function replaces the value at the specified index with a new value.
  It is optimized for replacing the head element (index 0).

  ## Parameters

    - `series` - The DataSeries to update
    - `index` - Zero-based index where:
      - Positive: 0 is newest, 1 is second newest, etc.
      - Negative: -1 is oldest, -2 is second oldest, etc.
    - `value` - The new value to set at the index

  ## Returns

    - A new `DataSeries` with the value replaced
    - Returns the original series if the index is out of bounds

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> series = DataSeries.replace_at(series, 0, 99)
      iex> series[0]
      99
      iex> series[1]
      20

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> series = DataSeries.replace_at(series, -1, 99)
      iex> series[-1]
      99

  """
  @spec replace_at(t(), integer(), any()) :: t()
  def replace_at(%DataSeries{data: data, size: size} = series, index, value) do
    cond do
      # Optimize for head replacement (index 0)
      index == 0 ->
        case data do
          [_old | rest] -> %DataSeries{series | data: [value | rest]}
          [] -> series
        end

      # Out of bounds - return original series
      index < -size or index >= size ->
        series

      # General case - use List.replace_at
      true ->
        new_data = List.replace_at(data, index, value)
        %DataSeries{series | data: new_data}
    end
  end

  @doc """
  Returns the list of all values in the DataSeries.

  The values are returned in reverse chronological order (newest first).

  ## Parameters

    - `series` - The DataSeries to get values from

  ## Returns

    - A list of values

  ## Examples

      iex> series = DataSeries.new()
      iex> series = series |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> DataSeries.values(series)
      [30, 20, 10]

      iex> series = DataSeries.new()
      iex> DataSeries.values(series)
      []

  """
  @spec values(t()) :: [any()]
  def values(%DataSeries{data: data}) do
    data
  end

  @doc """
  Adds a new value to the DataSeries.

  The new value is added at index 0 (newest position). If the DataSeries has reached
  its `max_size`, the oldest value (at the tail) is dropped to make room for the new value.

  ## Parameters

    - `series` - The DataSeries to add the value to
    - `value` - The value to add (can be any type)

  ## Returns

    - A new `DataSeries` with the value added

  ## Behavior

  - **When max_size is :infinity**: The value is added and size increases
  - **When size < max_size**: The value is added and size increases
  - **When size == max_size**: The value is added, the oldest value is dropped, size stays constant

  ## Examples

      # Adding to an infinite DataSeries
      iex> series = DataSeries.new()
      iex> series = DataSeries.add(series, 10)
      iex> series = DataSeries.add(series, 20)
      iex> DataSeries.size(series)
      2
      iex> series[0]
      20
      iex> series[1]
      10

      # Circular buffer with max_size
      iex> series = DataSeries.new(max_size: 3)
      iex> series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)
      iex> series[0]
      3
      iex> series[2]
      1
      iex> series = DataSeries.add(series, 4)  # Drops 1
      iex> series[0]
      4
      iex> series[1]
      3
      iex> series[2]
      2
      iex> DataSeries.size(series)
      3

      # Can store any type
      iex> series = DataSeries.new()
      iex> series = series |> DataSeries.add("hello") |> DataSeries.add(:atom) |> DataSeries.add(42)
      iex> series[0]
      42
      iex> series[1]
      :atom
      iex> series[2]
      "hello"

  """
  @spec add(t(), any()) :: t()
  def add(%DataSeries{} = series, value) do
    %DataSeries{data: data, size: size, max_size: max_size} = series

    {new_data, new_size} =
      cond do
        max_size == :infinity ->
          {[value | data], size + 1}

        size + 1 <= max_size ->
          {[value | data], size + 1}

        true ->
          data_tl = data |> Enum.reverse() |> tl() |> Enum.reverse()
          {[value | data_tl], size}
      end

    %DataSeries{series | data: new_data, size: new_size}
  end

  ## Access behaviour

  @doc """
  Fetches the value(s) at the given index or range from the DataSeries.

  This function is part of the `Access` behaviour and allows using bracket syntax
  (`series[index]` or `series[range]`) and `get_in/2` to access values.

  Supports negative indices like `Enum.at/2`: -1 is the oldest value, -2 is the
  second oldest, etc.

  ## Parameters

    - `series` - The DataSeries to fetch from
    - `index` - Zero-based index where:
      - Positive: 0 is newest, 1 is second newest, etc.
      - Negative: -1 is oldest, -2 is second oldest, etc.
    - `range` - A range like `1..5` or `-3..-1//1` to fetch a slice of values

  ## Returns

    - `{:ok, value}` if the index is valid
    - `{:ok, list}` if a range is provided (may be empty list)
    - `:error` if the index is out of bounds (for integer indices only)

  ## Examples

      # Positive indices
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> Access.fetch(series, 0)
      {:ok, 30}
      iex> Access.fetch(series, 1)
      {:ok, 20}
      iex> Access.fetch(series, 2)
      {:ok, 10}

      # Negative indices
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> Access.fetch(series, -1)
      {:ok, 10}
      iex> Access.fetch(series, -2)
      {:ok, 20}
      iex> Access.fetch(series, -3)
      {:ok, 30}

      # Range with positive indices
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30) |> DataSeries.add(40) |> DataSeries.add(50)
      iex> Access.fetch(series, 1..3)
      {:ok, [40, 30, 20]}

      # Range with negative indices
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30) |> DataSeries.add(40) |> DataSeries.add(50)
      iex> Access.fetch(series, -3..-1//1)
      {:ok, [30, 20, 10]}

      # Range with mixed indices
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30) |> DataSeries.add(40) |> DataSeries.add(50)
      iex> Access.fetch(series, 1..-2//1)
      {:ok, [40, 30, 20]}

      # Empty range
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> Access.fetch(series, 1..0//1)
      {:ok, []}

      # Out of bounds
      iex> series = DataSeries.new() |> DataSeries.add(10)
      iex> Access.fetch(series, 1)
      :error
      iex> Access.fetch(series, -2)
      :error

      # Using bracket syntax with integer
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> series[0]
      20
      iex> series[-1]
      10

      # Using bracket syntax with range
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> series[0..1]
      [30, 20]

      # Using get_in/2 with integer
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> get_in(series, [0])
      20
      iex> get_in(series, [-1])
      10

  """
  @impl Access
  def fetch(%DataSeries{data: data, size: size}, index) when is_integer(index) do
    case index >= -size and index < size do
      true -> {:ok, Enum.at(data, index)}
      false -> :error
    end
  end

  def fetch(%DataSeries{data: data}, %Range{} = range) do
    {:ok, Enum.slice(data, range)}
  end

  @doc """
  Gets the value at the given index and updates it with a function.

  This function is part of the `Access` behaviour and allows using `update_in/3` and
  `get_and_update_in/3` to modify values in the DataSeries.

  Supports negative indices like `Enum.at/2`: -1 is the oldest value, -2 is the
  second oldest, etc.

  **Important**: This function raises an `ArgumentError` if:
  - The index is out of bounds
  - The function returns `:pop` (popping is not supported for DataSeries)

  ## Parameters

    - `series` - The DataSeries to update
    - `index` - Zero-based index of the value to update where:
      - Positive: 0 is newest, 1 is second newest, etc.
      - Negative: -1 is oldest, -2 is second oldest, etc.
    - `function` - A function that receives the current value and returns
      `{get_value, new_value}` where `get_value` is returned and `new_value` replaces
      the current value

  ## Returns

    - `{get_value, new_series}` where `get_value` is from the function and `new_series`
      is the updated DataSeries

  ## Raises

    - `ArgumentError` if index is out of bounds
    - `ArgumentError` if function returns `:pop`

  ## Examples

      # Using Access.get_and_update/3 directly with positive index
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> {old, new_series} = Access.get_and_update(series, 0, fn val -> {val, val * 2} end)
      iex> old
      20
      iex> new_series[0]
      40
      iex> series[0]  # Original unchanged
      20

      # Using negative index
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> {old, new_series} = Access.get_and_update(series, -1, fn val -> {val, val * 10} end)
      iex> old
      10
      iex> new_series[-1]
      100

      # Using update_in/3 with negative index
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> new_series = update_in(series, [-1], fn val -> val + 5 end)
      iex> new_series[-1]
      15
      iex> series[-1]
      10

      # Using get_and_update_in/3
      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> {old, new_series} = get_and_update_in(series, [0], fn val -> {val * 10, val + 1} end)
      iex> old
      200
      iex> new_series[0]
      21

      # Out of bounds raises error
      iex> series = DataSeries.new() |> DataSeries.add(10)
      iex> Access.get_and_update(series, 5, fn val -> {val, val * 2} end)
      ** (ArgumentError) index 5 out of bounds for DataSeries of size 1

      # Negative index out of bounds
      iex> series = DataSeries.new() |> DataSeries.add(10)
      iex> Access.get_and_update(series, -5, fn val -> {val, val * 2} end)
      ** (ArgumentError) index -5 out of bounds for DataSeries of size 1

      # Returning :pop raises error
      iex> series = DataSeries.new() |> DataSeries.add(10)
      iex> Access.get_and_update(series, 0, fn _val -> :pop end)
      ** (ArgumentError) cannot pop from a DataSeries

  """
  @impl Access
  def get_and_update(%DataSeries{data: data, size: size} = series, index, function)
      when is_integer(index) do
    if index < -size or index >= size do
      raise ArgumentError, "index #{index} out of bounds for DataSeries of size #{size}"
    end

    current_value = Enum.at(data, index)

    case function.(current_value) do
      {get_value, new_value} ->
        new_data = List.replace_at(data, index, new_value)
        new_series = %DataSeries{series | data: new_data}
        {get_value, new_series}

      :pop ->
        raise ArgumentError, "cannot pop from a DataSeries"
    end
  end

  @doc """
  Pop is not supported for DataSeries.

  This function is part of the `Access` behaviour but always raises an error because
  popping values from a DataSeries is not a supported operation.

  ## Raises

    - Always raises a RuntimeError with message "you cannot pop a DataSeries"

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10)
      iex> Access.pop(series, 0)
      ** (RuntimeError) you cannot pop a DataSeries

      # pop_in/2 will also raise
      iex> series = DataSeries.new() |> DataSeries.add(10)
      iex> pop_in(series, [0])
      ** (RuntimeError) you cannot pop a DataSeries

  """
  @impl Access
  def pop(_data, _key) do
    raise "you cannot pop a DataSeries"
  end
end

defimpl Enumerable, for: TheoryCraft.DataSeries do
  @moduledoc """
  Enumerable protocol implementation for DataSeries.

  This allows using all `Enum` functions on a DataSeries. The enumeration order
  is the same as the internal list order (newest to oldest).
  """

  alias TheoryCraft.DataSeries

  @doc """
  Returns the number of elements in the DataSeries.

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> Enumerable.count(series)
      {:ok, 2}

  """
  def count(%DataSeries{size: size}) do
    {:ok, size}
  end

  @doc """
  Checks if a value is a member of the DataSeries.

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)
      iex> Enumerable.member?(series, 10)
      {:ok, true}
      iex> Enumerable.member?(series, 30)
      {:ok, false}

  """
  def member?(%DataSeries{data: data}, element) do
    {:ok, element in data}
  end

  @doc """
  Reduces the DataSeries to a single value.

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> Enumerable.reduce(series, {:cont, 0}, fn x, acc -> {:cont, x + acc} end)
      {:done, 60}

  """
  def reduce(%DataSeries{data: data}, acc, fun) do
    Enumerable.List.reduce(data, acc, fun)
  end

  @doc """
  Returns a slice of the DataSeries.

  ## Examples

      iex> series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)
      iex> {:ok, size, slicer} = Enumerable.slice(series)
      iex> size
      3
      iex> slicer.(0, 2, 1)
      [30, 20]

  """
  def slice(%DataSeries{data: data, size: size}) do
    slicer = fn start, length, step ->
      data
      |> Enum.slice(start, length)
      |> Enum.take_every(step)
    end

    {:ok, size, slicer}
  end
end

defimpl Inspect, for: TheoryCraft.DataSeries do
  @moduledoc """
  Inspect protocol implementation for DataSeries.

  Provides a human-readable representation of the DataSeries structure.
  """

  import Inspect.Algebra

  def inspect(%TheoryCraft.DataSeries{data: data, size: size, max_size: max_size}, opts) do
    concat([
      "#DataSeries<",
      to_doc(data, opts),
      ", size: ",
      to_string(size),
      ", max: ",
      to_string(max_size),
      ">"
    ])
  end
end
