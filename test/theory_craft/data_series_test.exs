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

  describe "Access.fetch/2 with integers" do
    test "fetches value at valid index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Access.fetch(series, 0) == {:ok, 30}
      assert Access.fetch(series, 1) == {:ok, 20}
      assert Access.fetch(series, 2) == {:ok, 10}
    end

    test "returns :error for out of bounds index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      assert Access.fetch(series, 2) == :error
      assert Access.fetch(series, 5) == :error
      assert Access.fetch(series, 100) == :error
    end

    test "supports negative indices" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      # -1 is oldest, -2 is second oldest, etc.
      assert Access.fetch(series, -1) == {:ok, 10}
      assert Access.fetch(series, -2) == {:ok, 20}
      assert Access.fetch(series, -3) == {:ok, 30}
    end

    test "returns :error for out of bounds negative index" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert Access.fetch(series, -2) == :error
      assert Access.fetch(series, -5) == :error
    end

    test "returns :error for empty DataSeries" do
      series = DataSeries.new()

      assert Access.fetch(series, 0) == :error
    end

    test "works with bracket syntax" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert series[0] == 30
      assert series[1] == 20
      assert series[2] == 10
      assert series[3] == nil
    end

    test "works with bracket syntax and negative indices" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert series[-1] == 10
      assert series[-2] == 20
      assert series[-3] == 30
      assert series[-4] == nil
    end

    test "works with get_in/2" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert get_in(series, [0]) == 30
      assert get_in(series, [1]) == 20
      assert get_in(series, [2]) == 10
      assert get_in(series, [3]) == nil
    end

    test "works with get_in/2 and negative indices" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert get_in(series, [-1]) == 10
      assert get_in(series, [-2]) == 20
      assert get_in(series, [-3]) == 30
      assert get_in(series, [-4]) == nil
    end
  end

  describe "Access.fetch/2 with ranges" do
    test "fetches slice with positive range" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)
        |> DataSeries.add(50)

      assert Access.fetch(series, 0..2) == {:ok, [50, 40, 30]}
      assert Access.fetch(series, 1..3) == {:ok, [40, 30, 20]}
      assert Access.fetch(series, 0..4) == {:ok, [50, 40, 30, 20, 10]}
    end

    test "fetches slice with negative range" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)
        |> DataSeries.add(50)

      assert Access.fetch(series, -3..-1//1) == {:ok, [30, 20, 10]}
      assert Access.fetch(series, -5..-3//1) == {:ok, [50, 40, 30]}
      assert Access.fetch(series, -2..-1//1) == {:ok, [20, 10]}
    end

    test "fetches slice with mixed positive and negative indices" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)
        |> DataSeries.add(50)

      assert Access.fetch(series, 1..-2//1) == {:ok, [40, 30, 20]}
      assert Access.fetch(series, 0..-1//1) == {:ok, [50, 40, 30, 20, 10]}
      assert Access.fetch(series, 2..-1//1) == {:ok, [30, 20, 10]}
    end

    test "returns empty list for empty range" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Access.fetch(series, 2..1//1) == {:ok, []}
      assert Access.fetch(series, 1..0//1) == {:ok, []}
    end

    test "handles range that goes beyond bounds" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      # Enum.slice handles out of bounds gracefully
      assert Access.fetch(series, 0..10) == {:ok, [30, 20, 10]}
      assert Access.fetch(series, 2..10) == {:ok, [10]}
    end

    test "works with bracket syntax and range" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)
        |> DataSeries.add(50)

      assert series[0..2] == [50, 40, 30]
      assert series[1..3] == [40, 30, 20]
      assert series[-3..-1//1] == [30, 20, 10]
    end

    test "single element range" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Access.fetch(series, 0..0) == {:ok, [30]}
      assert Access.fetch(series, 1..1) == {:ok, [20]}
      assert Access.fetch(series, -1..-1//1) == {:ok, [10]}
    end

    test "range on empty DataSeries returns empty list" do
      series = DataSeries.new()

      assert Access.fetch(series, 0..2) == {:ok, []}
      assert Access.fetch(series, -3..-1//1) == {:ok, []}
    end

    test "range with step (using //)" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)
        |> DataSeries.add(50)
        |> DataSeries.add(60)

      # Every other element
      assert Access.fetch(series, 0..4//2) == {:ok, [60, 40, 20]}
      assert Access.fetch(series, 1..5//2) == {:ok, [50, 30, 10]}
    end
  end

  describe "Access.get_and_update/3" do
    test "updates value at valid index" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      {old_value, new_series} = Access.get_and_update(series, 0, fn val -> {val, val * 2} end)

      assert old_value == 20
      assert new_series[0] == 40
      assert new_series[1] == 10
    end

    test "returns {old_value, new_data_series}" do
      series = DataSeries.new() |> DataSeries.add(100)

      {old_value, new_series} = Access.get_and_update(series, 0, fn val -> {val + 1, val + 2} end)

      assert old_value == 101
      assert new_series[0] == 102
    end

    test "raises for out of bounds index" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert_raise ArgumentError, ~r/index 5 out of bounds for DataSeries of size 1/, fn ->
        Access.get_and_update(series, 5, fn val -> {val, val * 2} end)
      end
    end

    test "supports negative indices" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      {old_value, new_series} = Access.get_and_update(series, -1, fn val -> {val, val * 2} end)

      assert old_value == 10
      assert new_series[-1] == 20
      assert new_series[0] == 30
      assert new_series[1] == 20
    end

    test "raises for out of bounds negative index" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert_raise ArgumentError, ~r/index -2 out of bounds for DataSeries of size 1/, fn ->
        Access.get_and_update(series, -2, fn val -> {val, val * 2} end)
      end
    end

    test "raises when function returns :pop" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert_raise ArgumentError, ~r/cannot pop from a DataSeries/, fn ->
        Access.get_and_update(series, 0, fn _val -> :pop end)
      end
    end

    test "works with update_in/3" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      new_series = update_in(series, [0], fn val -> val + 5 end)

      assert new_series[0] == 35
      assert new_series[1] == 20
      assert new_series[2] == 10
    end

    test "works with get_and_update_in/3" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      {old_value, new_series} = get_and_update_in(series, [0], fn val -> {val * 10, val + 1} end)

      assert old_value == 200
      assert new_series[0] == 21
      assert new_series[1] == 10
    end

    test "works with Access.all() to update all elements" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      new_series = update_in(series.data, [Access.all()], fn val -> val * 10 end)

      assert new_series == [30, 20, 10]
    end
  end

  describe "Access.pop/2" do
    test "always raises error" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      assert_raise RuntimeError, "you cannot pop a DataSeries", fn ->
        Access.pop(series, 0)
      end
    end

    test "raises for any index" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert_raise RuntimeError, "you cannot pop a DataSeries", fn ->
        Access.pop(series, 0)
      end

      assert_raise RuntimeError, "you cannot pop a DataSeries", fn ->
        Access.pop(series, 1)
      end
    end

    test "pop_in/2 also raises" do
      series = DataSeries.new() |> DataSeries.add(10)

      assert_raise RuntimeError, "you cannot pop a DataSeries", fn ->
        pop_in(series, [0])
      end
    end
  end

  describe "integration with Kernel Access functions" do
    test "chaining get_in and update_in" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      value = get_in(series, [1])
      assert value == 20

      new_series = update_in(series, [1], fn val -> val * 2 end)
      assert get_in(new_series, [1]) == 40
    end

    test "get_and_update_in with complex transformation" do
      series = DataSeries.new() |> DataSeries.add(5) |> DataSeries.add(10) |> DataSeries.add(15)

      {doubled, new_series} =
        get_and_update_in(series, [0], fn val ->
          {val * 2, val + 1}
        end)

      assert doubled == 30
      assert new_series[0] == 16
    end

    test "accessing with bracket syntax and update_in together" do
      series = DataSeries.new() |> DataSeries.add(100) |> DataSeries.add(200)

      old_value = series[0]
      assert old_value == 200

      new_series = update_in(series, [0], fn val -> val / 2 end)

      assert new_series[0] == 100.0
    end

    test "update_in with negative indices" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      new_series = update_in(series, [-1], fn val -> val * 10 end)

      assert new_series[-1] == 100
      assert new_series[0] == 30
    end

    test "get_and_update_in with negative indices" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      {old_value, new_series} =
        get_and_update_in(series, [-2], fn val ->
          {val * 2, val + 5}
        end)

      assert old_value == 40
      assert new_series[-2] == 25
      assert new_series[0] == 30
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

  describe "Enumerable protocol - Enum.map/2" do
    test "maps over all values" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      result = Enum.map(series, fn x -> x * 2 end)

      assert result == [60, 40, 20]
    end

    test "maps empty DataSeries returns empty list" do
      series = DataSeries.new()

      result = Enum.map(series, fn x -> x * 2 end)

      assert result == []
    end

    test "maps with single element" do
      series = DataSeries.new() |> DataSeries.add(42)

      result = Enum.map(series, fn x -> x + 1 end)

      assert result == [43]
    end

    test "maps with different types" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      result = Enum.map(series, fn x -> "value_#{x}" end)

      assert result == ["value_3", "value_2", "value_1"]
    end
  end

  describe "Enumerable protocol - Enum.filter/2" do
    test "filters values based on predicate" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      result = Enum.filter(series, fn x -> x > 15 end)

      assert result == [30, 20]
    end

    test "filters returns empty list when no values match" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      result = Enum.filter(series, fn x -> x > 100 end)

      assert result == []
    end

    test "filters returns all values when all match" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      result = Enum.filter(series, fn x -> x > 0 end)

      assert result == [30, 20, 10]
    end

    test "filters empty DataSeries returns empty list" do
      series = DataSeries.new()

      result = Enum.filter(series, fn x -> x > 0 end)

      assert result == []
    end
  end

  describe "Enumerable protocol - Enum.reduce/3" do
    test "reduces to sum" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      result = Enum.reduce(series, 0, fn x, acc -> x + acc end)

      assert result == 60
    end

    test "reduces to product" do
      series = DataSeries.new() |> DataSeries.add(2) |> DataSeries.add(3) |> DataSeries.add(4)

      result = Enum.reduce(series, 1, fn x, acc -> x * acc end)

      assert result == 24
    end

    test "reduces empty DataSeries returns accumulator" do
      series = DataSeries.new()

      result = Enum.reduce(series, 42, fn x, acc -> x + acc end)

      assert result == 42
    end

    test "reduces to list (reverse chronological)" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      result = Enum.reduce(series, [], fn x, acc -> [x | acc] end)

      # Newest first in series, so result should be [1, 2, 3]
      assert result == [1, 2, 3]
    end
  end

  describe "Enumerable protocol - Enum.count/1" do
    test "counts elements in DataSeries" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Enum.count(series) == 3
    end

    test "counts empty DataSeries" do
      series = DataSeries.new()

      assert Enum.count(series) == 0
    end

    test "counts single element" do
      series = DataSeries.new() |> DataSeries.add(42)

      assert Enum.count(series) == 1
    end

    test "count is same as DataSeries.size/1" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert Enum.count(series) == DataSeries.size(series)
    end
  end

  describe "Enumerable protocol - Enum.member?/2" do
    test "checks if element is member" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Enum.member?(series, 10) == true
      assert Enum.member?(series, 20) == true
      assert Enum.member?(series, 30) == true
    end

    test "returns false for non-member" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      assert Enum.member?(series, 30) == false
      assert Enum.member?(series, 100) == false
    end

    test "returns false for empty DataSeries" do
      series = DataSeries.new()

      assert Enum.member?(series, 10) == false
    end

    test "works with different types" do
      series = DataSeries.new() |> DataSeries.add(:atom) |> DataSeries.add("string")

      assert Enum.member?(series, :atom) == true
      assert Enum.member?(series, "string") == true
      assert Enum.member?(series, :other) == false
    end
  end

  describe "Enumerable protocol - Enum.take/2" do
    test "takes first n elements" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)

      result = Enum.take(series, 2)

      assert result == [40, 30]
    end

    test "takes more than available returns all elements" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20)

      result = Enum.take(series, 10)

      assert result == [20, 10]
    end

    test "takes 0 returns empty list" do
      series = DataSeries.new() |> DataSeries.add(10)

      result = Enum.take(series, 0)

      assert result == []
    end

    test "takes from empty DataSeries returns empty list" do
      series = DataSeries.new()

      result = Enum.take(series, 5)

      assert result == []
    end
  end

  describe "Enumerable protocol - Enum.slice/2" do
    test "slices with range" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)
        |> DataSeries.add(50)

      result = Enum.slice(series, 1..3)

      assert result == [40, 30, 20]
    end

    test "slices with start and length" do
      series =
        DataSeries.new()
        |> DataSeries.add(10)
        |> DataSeries.add(20)
        |> DataSeries.add(30)
        |> DataSeries.add(40)

      result = Enum.slice(series, 1, 2)

      assert result == [30, 20]
    end

    test "slices empty DataSeries returns empty list" do
      series = DataSeries.new()

      result = Enum.slice(series, 0..2)

      assert result == []
    end
  end

  describe "Enumerable protocol - other Enum functions" do
    test "Enum.reverse/1" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      result = Enum.reverse(series)

      assert result == [10, 20, 30]
    end

    test "Enum.any?/2" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Enum.any?(series, fn x -> x > 25 end) == true
      assert Enum.any?(series, fn x -> x > 100 end) == false
    end

    test "Enum.all?/2" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Enum.all?(series, fn x -> x > 0 end) == true
      assert Enum.all?(series, fn x -> x > 15 end) == false
    end

    test "Enum.find/2" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Enum.find(series, fn x -> x > 15 end) == 30
      assert Enum.find(series, fn x -> x > 100 end) == nil
    end

    test "Enum.sum/1" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      assert Enum.sum(series) == 60
    end

    test "Enum.max/1" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(30) |> DataSeries.add(20)

      assert Enum.max(series) == 30
    end

    test "Enum.min/1" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(30) |> DataSeries.add(20)

      assert Enum.min(series) == 10
    end

    test "Enum.join/2" do
      series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert Enum.join(series, ", ") == "3, 2, 1"
    end

    test "Enum.with_index/1" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      result = Enum.with_index(series)

      assert result == [{30, 0}, {20, 1}, {10, 2}]
    end

    test "Enum.into/2 converts to list" do
      series = DataSeries.new() |> DataSeries.add(10) |> DataSeries.add(20) |> DataSeries.add(30)

      result = Enum.into(series, [])

      assert result == [30, 20, 10]
    end
  end

  describe "Enumerable protocol - integration with circular buffer" do
    test "enumerates over max_size DataSeries" do
      series = DataSeries.new(max_size: 3)

      series =
        series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3) |> DataSeries.add(4)

      result = Enum.to_list(series)

      # Should contain [4, 3, 2] (1 was dropped)
      assert result == [4, 3, 2]
    end

    test "Enum.count matches size after circular buffer overflow" do
      series = DataSeries.new(max_size: 2)
      series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert Enum.count(series) == 2
      assert DataSeries.size(series) == 2
    end

    test "Enum.member? works with circular buffer" do
      series = DataSeries.new(max_size: 2)
      series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)

      assert Enum.member?(series, 3) == true
      assert Enum.member?(series, 2) == true
      # Was dropped
      assert Enum.member?(series, 1) == false
    end
  end
end
