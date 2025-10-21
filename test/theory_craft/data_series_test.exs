defmodule TheoryCraft.DataSeriesTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.DataSeries

  ## Tests

  doctest TheoryCraft.DataSeries

  describe "new/1" do
    test "creates empty DataSeries with default max_size (:infinity)" do
      series = DataSeries.new()

      assert %DataSeries{} = series
      assert series.data == []
      assert series.size == 0
      assert series.max_size == :infinity
    end

    test "creates DataSeries with custom max_size" do
      series = DataSeries.new(max_size: 10)

      assert %DataSeries{} = series
      assert series.data == []
      assert series.size == 0
      assert series.max_size == 10
    end

    test "creates DataSeries with max_size 1" do
      series = DataSeries.new(max_size: 1)

      assert series.max_size == 1
    end
  end

  describe "add/2" do
    test "adds single value to empty DataSeries" do
      series = DataSeries.new()
      series = DataSeries.add(series, 42)

      assert DataSeries.size(series) == 1
      assert series[0] == 42
    end

    test "adds multiple values" do
      series = DataSeries.new()
      series = series |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert DataSeries.size(series) == 3
      assert series[0] == 30
      assert series[1] == 20
      assert series[2] == 10
    end

    test "values are in reverse chronological order (newest first)" do
      series =
        DataSeries.new()
        |> DataSeries.add("first")
        |> DataSeries.add("second")
        |> DataSeries.add("third")

      assert series[0] == "third"
      assert series[1] == "second"
      assert series[2] == "first"
    end

    test "with max_size :infinity, keeps growing" do
      series = DataSeries.new(max_size: :infinity)

      series =
        Enum.reduce(1..100, series, fn i, acc ->
          DataSeries.add(acc, i)
        end)

      assert DataSeries.size(series) == 100
    end

    test "with max_size limit, truncates oldest when limit reached" do
      series = DataSeries.new(max_size: 3)

      series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert DataSeries.size(series) == 3

      series = DataSeries.add(series, 4)

      assert DataSeries.size(series) == 3
      assert series[0] == 4
      assert series[1] == 3
      assert series[2] == 2
      # 1 was dropped
      assert series[3] == nil
    end

    test "circular buffer behavior: when full, drops oldest, keeps size constant" do
      series = DataSeries.new(max_size: 5)

      # Fill to capacity
      series =
        Enum.reduce(1..5, series, fn i, acc ->
          DataSeries.add(acc, i)
        end)

      assert DataSeries.size(series) == 5

      # Add more values
      series = series |> DataSeries.add(6) |> DataSeries.add(7) |> DataSeries.add(8)

      assert DataSeries.size(series) == 5
      assert series[0] == 8
      assert series[1] == 7
      assert series[2] == 6
      assert series[3] == 5
      assert series[4] == 4
    end

    test "can add any type of value" do
      series =
        DataSeries.new()
        |> DataSeries.add(42)
        |> DataSeries.add("string")
        |> DataSeries.add(:atom)
        |> DataSeries.add([1, 2, 3])
        |> DataSeries.add(%{key: "value"})

      assert series[0] == %{key: "value"}
      assert series[1] == [1, 2, 3]
      assert series[2] == :atom
      assert series[3] == "string"
      assert series[4] == 42
    end
  end

  describe "last/1" do
    test "returns most recent value (head of list)" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert DataSeries.last(series) == 30
    end

    test "returns nil for empty DataSeries" do
      series = DataSeries.new()

      assert DataSeries.last(series) == nil
    end

    test "returns the only value when size is 1" do
      series = DataSeries.new() |> DataSeries.add(42)

      assert DataSeries.last(series) == 42
    end

    test "last is always same as series[0]" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert DataSeries.last(series) == series[0]
    end
  end

  describe "size/1" do
    test "returns 0 for empty DataSeries" do
      series = DataSeries.new()

      assert DataSeries.size(series) == 0
    end

    test "returns correct size after additions" do
      series = DataSeries.new()

      assert DataSeries.size(series) == 0

      series = DataSeries.add(series, 1)
      assert DataSeries.size(series) == 1

      series = DataSeries.add(series, 2)
      assert DataSeries.size(series) == 2

      series = DataSeries.add(series, 3)
      assert DataSeries.size(series) == 3
    end

    test "size stays at max_size when circular buffer is full" do
      series = DataSeries.new(max_size: 3)

      series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)
      assert DataSeries.size(series) == 3

      series = series |> DataSeries.add(4) |> DataSeries.add(5)
      assert DataSeries.size(series) == 3
    end
  end

  describe "at/2" do
    test "returns value at valid positive index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert DataSeries.at(series, 0) == 30
      assert DataSeries.at(series, 1) == 20
      assert DataSeries.at(series, 2) == 10
    end

    test "returns value at valid negative index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert DataSeries.at(series, -1) == 10
      assert DataSeries.at(series, -2) == 20
      assert DataSeries.at(series, -3) == 30
    end

    test "returns nil for out of bounds positive index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      assert DataSeries.at(series, 2) == nil
      assert DataSeries.at(series, 10) == nil
    end

    test "returns nil for out of bounds negative index" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert DataSeries.at(series, -2) == nil
      assert DataSeries.at(series, -10) == nil
    end

    test "returns nil for empty DataSeries" do
      series = DataSeries.new()

      assert DataSeries.at(series, 0) == nil
      assert DataSeries.at(series, -1) == nil
    end

    test "returns single value when size is 1" do
      series = DataSeries.new() |> DataSeries.add(42)

      assert DataSeries.at(series, 0) == 42
      assert DataSeries.at(series, -1) == 42
    end

    test "works with different data types" do
      series =
        DataSeries.new()
        |> DataSeries.add(:atom)
        |> DataSeries.add("string")
        |> DataSeries.add(123)

      assert DataSeries.at(series, 0) == 123
      assert DataSeries.at(series, 1) == "string"
      assert DataSeries.at(series, 2) == :atom
    end
  end

  describe "Access protocol" do
    test "bracket syntax works with positive index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert series[0] == 30
      assert series[1] == 20
      assert series[2] == 10
      assert series[3] == nil
    end

    test "bracket syntax works with negative indices" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert series[-1] == 10
      assert series[-2] == 20
      assert series[-3] == 30
      assert series[-4] == nil
    end

    test "bracket syntax works with get_in" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert get_in(series, [0]) == 30
      assert get_in(series, [1]) == 20
      assert get_in(series, [-1]) == 10
      assert get_in(series, [5]) == nil
    end

    test "fetches value at valid positive index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Access.fetch(series, 0) == {:ok, 30}
      assert Access.fetch(series, 1) == {:ok, 20}
      assert Access.fetch(series, 2) == {:ok, 10}
    end

    test "fetches value at valid negative index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Access.fetch(series, -1) == {:ok, 10}
      assert Access.fetch(series, -2) == {:ok, 20}
      assert Access.fetch(series, -3) == {:ok, 30}
    end

    test "returns :error for out of bounds index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      assert Access.fetch(series, 2) == :error
      assert Access.fetch(series, -3) == :error
    end

    test "fetches slice with range" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)
        |> DataSeries.add(50)

      assert Access.fetch(series, 0..2) == {:ok, [50, 40, 30]}
      assert Access.fetch(series, 1..3) == {:ok, [40, 30, 20]}
    end

    test "get_and_update updates value at valid index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      {old_value, new_series} = Access.get_and_update(series, 0, fn val -> {val, val * 2} end)

      assert old_value == 20
      assert new_series[0] == 40
      assert new_series[1] == 10
    end

    test "get_and_update raises when function returns :pop" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert_raise ArgumentError, ~r/cannot pop from a DataSeries/, fn ->
        Access.get_and_update(series, 0, fn _val -> :pop end)
      end
    end

    test "pop always raises error" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      assert_raise RuntimeError, "you cannot pop a DataSeries", fn ->
        Access.pop(series, 0)
      end
    end
  end

  describe "replace_at/3" do
    test "replaces value at index 0 (head)" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      new_series = DataSeries.replace_at(series, 0, 99)

      assert new_series[0] == 99
      assert new_series[1] == 20
      assert new_series[2] == 10
      assert DataSeries.size(new_series) == 3
    end

    test "replaces value at positive index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      new_series = DataSeries.replace_at(series, 1, 99)

      assert new_series[0] == 30
      assert new_series[1] == 99
      assert new_series[2] == 10
    end

    test "replaces value at negative index -1 (tail)" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      new_series = DataSeries.replace_at(series, -1, 99)

      assert new_series[0] == 30
      assert new_series[1] == 20
      assert new_series[-1] == 99
    end

    test "replaces value at negative index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      new_series = DataSeries.replace_at(series, -2, 99)

      assert new_series[0] == 30
      assert new_series[-2] == 99
      assert new_series[-1] == 10
    end

    test "returns original series if index out of bounds" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      new_series = DataSeries.replace_at(series, 5, 99)

      assert new_series == series
      assert new_series[0] == 20
      assert new_series[1] == 10
    end

    test "returns original series if negative index out of bounds" do
      series = DataSeries.new() |> DataSeries.add(10)

      new_series = DataSeries.replace_at(series, -5, 99)

      assert new_series == series
      assert new_series[0] == 10
    end

    test "works with empty series" do
      series = DataSeries.new()

      new_series = DataSeries.replace_at(series, 0, 99)

      assert new_series == series
      assert DataSeries.size(new_series) == 0
    end
  end

  describe "values/1" do
    test "returns list of values in reverse chronological order" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert DataSeries.values(series) == [30, 20, 10]
    end

    test "returns empty list for empty DataSeries" do
      series = DataSeries.new()

      assert DataSeries.values(series) == []
    end

    test "returns updated list after circular buffer overflow" do
      series = DataSeries.new(max_size: 2)
      series = series |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert DataSeries.values(series) == [30, 20]
    end

    test "returns all values with mixed types" do
      series =
        DataSeries.new()
        |> DataSeries.add(42)
        |> DataSeries.add("string")
        |> DataSeries.add(:atom)

      assert DataSeries.values(series) == [:atom, "string", 42]
    end
  end

  describe "edge cases" do
    test "max_size of 1 works correctly" do
      series = DataSeries.new(max_size: 1)

      series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert DataSeries.size(series) == 1
      assert series[0] == 3
      assert series[1] == nil
    end

    test "adding nil values" do
      series =
        DataSeries.new() |> DataSeries.add(nil) |> DataSeries.add(10) |> DataSeries.add(nil)

      assert series[0] == nil
      assert series[1] == 10
      assert series[2] == nil
    end

    test "update_in with function that returns same value" do
      series = DataSeries.new() |> DataSeries.add(42)

      new_series = update_in(series, [0], fn val -> val end)

      assert new_series[0] == 42
      assert DataSeries.size(new_series) == 1
    end

    test "large number of additions with infinite size" do
      series = DataSeries.new()

      series =
        Enum.reduce(1..1000, series, fn i, acc ->
          DataSeries.add(acc, i)
        end)

      assert DataSeries.size(series) == 1000
      assert series[0] == 1000
      assert series[999] == 1
    end

    test "accessing exactly at boundary" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      # Size is 3, so indices 0, 1, 2 are valid, 3 is not
      assert series[2] == 1
      assert series[3] == nil
      assert Access.fetch(series, 2) == {:ok, 1}
      assert Access.fetch(series, 3) == :error
    end
  end

  describe "Enumerable protocol" do
    test "Enum.count matches DataSeries.size" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert Enum.count(series) == DataSeries.size(series)
    end

    test "enumerates over circular buffer correctly" do
      series = DataSeries.new(max_size: 3)

      series =
        series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3) |> DataSeries.add(4)

      result = Enum.to_list(series)

      # Should contain [4, 3, 2] (1 was dropped)
      assert result == [4, 3, 2]
    end
  end
end
