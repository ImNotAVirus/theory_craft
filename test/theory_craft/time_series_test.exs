defmodule TheoryCraft.TimeSeriesTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.TimeSeries

  ## Tests

  doctest TheoryCraft.TimeSeries

  describe "new/1" do
    test "creates empty TimeSeries with default max_size (:infinity)" do
      ts = TimeSeries.new()

      assert %TimeSeries{} = ts
      assert ts.data.data == []
      assert ts.dt == []
      assert TimeSeries.size(ts) == 0
      assert ts.data.max_size == :infinity
    end

    test "creates TimeSeries with custom max_size" do
      ts = TimeSeries.new(max_size: 10)

      assert %TimeSeries{} = ts
      assert ts.data.max_size == 10
      assert TimeSeries.size(ts) == 0
    end
  end

  describe "add/3" do
    test "adds single value to empty TimeSeries" do
      ts = TimeSeries.new()
      ts = TimeSeries.add(ts, dt1(), 100.0)

      assert TimeSeries.size(ts) == 1
      assert ts[dt1()] == 100.0
    end

    test "adds multiple values in chronological order" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.size(ts) == 3
      assert ts[0] == 102.0
      assert ts[1] == 101.0
      assert ts[2] == 100.0
    end

    test "raises when datetime equals last datetime" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise ArgumentError, ~r/datetime must be strictly greater/, fn ->
        TimeSeries.add(ts, dt1(), 105.0)
      end
    end

    test "raises when datetime is less than last datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert_raise ArgumentError, ~r/datetime must be strictly greater/, fn ->
        TimeSeries.add(ts, dt1(), 100.0)
      end
    end

    test "maintains synchronization between data and dt" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert length(ts.dt) == TimeSeries.size(ts)
      assert Enum.at(ts.dt, 0) == dt3()
      assert Enum.at(ts.dt, 1) == dt2()
      assert Enum.at(ts.dt, 2) == dt1()
    end

    test "circular buffer behavior with max_size" do
      ts =
        TimeSeries.new(max_size: 3)
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.size(ts) == 3

      ts = TimeSeries.add(ts, dt4(), 103.0)

      assert TimeSeries.size(ts) == 3
      assert ts[0] == 103.0
      assert ts[1] == 102.0
      assert ts[2] == 101.0
      # dt1/100.0 was dropped
      assert length(ts.dt) == 3
    end
  end

  describe "update/3" do
    test "inserts value when datetime > last datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.update(dt1(), 100.0)
        |> TimeSeries.update(dt2(), 101.0)

      assert TimeSeries.size(ts) == 2
      assert ts[0] == 101.0
      assert ts[1] == 100.0
    end

    test "updates value when datetime == last datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.update(dt1(), 100.0)
        |> TimeSeries.update(dt1(), 105.0)

      assert TimeSeries.size(ts) == 1
      assert ts[0] == 105.0
    end

    test "raises when datetime < last datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.update(dt2(), 101.0)

      assert_raise ArgumentError, ~r/datetime must be >= the last datetime/, fn ->
        TimeSeries.update(ts, dt1(), 100.0)
      end
    end

    test "works on empty TimeSeries" do
      ts = TimeSeries.new()
      ts = TimeSeries.update(ts, dt1(), 100.0)

      assert TimeSeries.size(ts) == 1
      assert ts[0] == 100.0
    end

    test "maintains synchronization when updating" do
      ts =
        TimeSeries.new()
        |> TimeSeries.update(dt1(), 100.0)
        |> TimeSeries.update(dt2(), 101.0)
        |> TimeSeries.update(dt2(), 105.0)

      assert TimeSeries.size(ts) == 2
      assert length(ts.dt) == 2
      assert ts[0] == 105.0
    end

    test "circular buffer behavior with max_size" do
      ts =
        TimeSeries.new(max_size: 2)
        |> TimeSeries.update(dt1(), 100.0)
        |> TimeSeries.update(dt2(), 101.0)
        |> TimeSeries.update(dt3(), 102.0)

      assert TimeSeries.size(ts) == 2
      assert ts[0] == 102.0
      assert ts[1] == 101.0
    end
  end

  describe "last/1" do
    test "returns value for most recent element" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.last(ts) == 102.0
    end

    test "returns nil for empty TimeSeries" do
      ts = TimeSeries.new()

      assert TimeSeries.last(ts) == nil
    end

    test "returns correct value after update" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.update(dt1(), 105.0)

      assert TimeSeries.last(ts) == 105.0
    end
  end

  describe "size/1" do
    test "returns 0 for empty TimeSeries" do
      ts = TimeSeries.new()

      assert TimeSeries.size(ts) == 0
    end

    test "returns correct size after additions" do
      ts = TimeSeries.new()
      assert TimeSeries.size(ts) == 0

      ts = TimeSeries.add(ts, dt1(), 100.0)
      assert TimeSeries.size(ts) == 1

      ts = TimeSeries.add(ts, dt2(), 101.0)
      assert TimeSeries.size(ts) == 2

      ts = TimeSeries.add(ts, dt3(), 102.0)
      assert TimeSeries.size(ts) == 3
    end

    test "size stays at max_size when circular buffer is full" do
      ts =
        TimeSeries.new(max_size: 3)
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.size(ts) == 3

      ts = ts |> TimeSeries.add(dt4(), 103.0) |> TimeSeries.add(dt5(), 104.0)
      assert TimeSeries.size(ts) == 3
    end
  end

  describe "at/2 with integer index" do
    test "returns value at valid index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.at(ts, 0) == 102.0
      assert TimeSeries.at(ts, 1) == 101.0
      assert TimeSeries.at(ts, 2) == 100.0
    end

    test "supports negative indices" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.at(ts, -1) == 100.0
      assert TimeSeries.at(ts, -2) == 101.0
      assert TimeSeries.at(ts, -3) == 102.0
    end

    test "returns nil for out of bounds index" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert TimeSeries.at(ts, 1) == nil
      assert TimeSeries.at(ts, -2) == nil
    end
  end

  describe "at/2 with DateTime" do
    test "returns value at exact datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert TimeSeries.at(ts, dt1()) == 100.0
      assert TimeSeries.at(ts, dt2()) == 101.0
    end

    test "returns nil for non-existent datetime" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert TimeSeries.at(ts, dt2()) == nil
    end

    test "returns nil for empty TimeSeries" do
      ts = TimeSeries.new()

      assert TimeSeries.at(ts, dt1()) == nil
    end
  end

  describe "replace_at/3 with integer index" do
    test "replaces value at index 0 (head)" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      new_ts = TimeSeries.replace_at(ts, 0, 999.0)

      assert new_ts[0] == 999.0
      assert new_ts[1] == 101.0
      assert new_ts[2] == 100.0
      assert TimeSeries.size(new_ts) == 3
    end

    test "replaces value at positive index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      new_ts = TimeSeries.replace_at(ts, 1, 999.0)

      assert new_ts[0] == 101.0
      assert new_ts[1] == 999.0
    end

    test "replaces value at negative index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      new_ts = TimeSeries.replace_at(ts, -1, 999.0)

      assert new_ts[-1] == 999.0
      assert new_ts[0] == 101.0
    end

    test "returns original series if index out of bounds" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      new_ts = TimeSeries.replace_at(ts, 5, 999.0)

      assert new_ts == ts
      assert new_ts[0] == 100.0
    end
  end

  describe "replace_at/3 with DateTime" do
    test "replaces value at datetime (head)" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      new_ts = TimeSeries.replace_at(ts, dt2(), 999.0)

      assert new_ts[dt2()] == 999.0
      assert new_ts[dt1()] == 100.0
    end

    test "replaces value at datetime (middle)" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      new_ts = TimeSeries.replace_at(ts, dt2(), 999.0)

      assert new_ts[dt2()] == 999.0
      assert new_ts[dt1()] == 100.0
      assert new_ts[dt3()] == 102.0
    end

    test "returns original series if datetime not found" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      new_ts = TimeSeries.replace_at(ts, dt2(), 999.0)

      assert new_ts == ts
      assert new_ts[dt1()] == 100.0
    end
  end

  describe "keys/1" do
    test "returns list of datetimes in reverse chronological order" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.keys(ts) == [dt3(), dt2(), dt1()]
    end

    test "returns empty list for empty TimeSeries" do
      ts = TimeSeries.new()

      assert TimeSeries.keys(ts) == []
    end

    test "returns updated list after circular buffer overflow" do
      ts =
        TimeSeries.new(max_size: 2)
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.keys(ts) == [dt3(), dt2()]
    end
  end

  describe "values/1" do
    test "returns list of values in reverse chronological order" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.values(ts) == [102.0, 101.0, 100.0]
    end

    test "returns empty list for empty TimeSeries" do
      ts = TimeSeries.new()

      assert TimeSeries.values(ts) == []
    end

    test "returns updated list after circular buffer overflow" do
      ts =
        TimeSeries.new(max_size: 2)
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.values(ts) == [102.0, 101.0]
    end

    test "values correspond to keys in the same order" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      keys = TimeSeries.keys(ts)
      values = TimeSeries.values(ts)

      assert Enum.zip(keys, values) == [{dt3(), 102.0}, {dt2(), 101.0}, {dt1(), 100.0}]
    end
  end

  describe "Access.fetch/2 with integer index" do
    test "fetches value at valid index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert Access.fetch(ts, 0) == {:ok, 102.0}
      assert Access.fetch(ts, 1) == {:ok, 101.0}
      assert Access.fetch(ts, 2) == {:ok, 100.0}
    end

    test "supports negative indices" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Access.fetch(ts, -1) == {:ok, 100.0}
      assert Access.fetch(ts, -2) == {:ok, 101.0}
    end

    test "returns :error for out of bounds" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert Access.fetch(ts, 1) == :error
      assert Access.fetch(ts, -2) == :error
    end

    test "works with bracket syntax" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert ts[0] == 101.0
      assert ts[1] == 100.0
      assert ts[2] == nil
    end
  end

  describe "Access.fetch/2 with DateTime" do
    test "fetches value at exact datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Access.fetch(ts, dt1()) == {:ok, 100.0}
      assert Access.fetch(ts, dt2()) == {:ok, 101.0}
    end

    test "returns :error for non-existent datetime" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert Access.fetch(ts, dt2()) == :error
    end

    test "works with bracket syntax" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert ts[dt1()] == 100.0
      assert ts[dt2()] == 101.0
      assert ts[dt3()] == nil
    end

    test "returns {:ok, nil} when nil value is stored" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), nil)
        |> TimeSeries.add(dt2(), 101.0)

      assert Access.fetch(ts, dt1()) == {:ok, nil}
      assert Access.fetch(ts, dt2()) == {:ok, 101.0}
    end
  end

  describe "Access.fetch/2 with Range" do
    test "fetches slice of values" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)
        |> TimeSeries.add(dt4(), 103.0)

      assert Access.fetch(ts, 0..2) == {:ok, [103.0, 102.0, 101.0]}
      assert Access.fetch(ts, 1..2) == {:ok, [102.0, 101.0]}
    end

    test "supports negative ranges" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert Access.fetch(ts, -2..-1//1) == {:ok, [101.0, 100.0]}
    end

    test "returns empty list for empty range" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert Access.fetch(ts, 1..0//1) == {:ok, []}
    end

    test "works with bracket syntax" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert ts[0..1] == [102.0, 101.0]
    end
  end

  describe "Access.get_and_update/3 with integer index" do
    test "updates value at index and returns {old_value, new_ts}" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      {old, new_ts} = Access.get_and_update(ts, 0, fn val -> {val, val * 2} end)

      assert old == 101.0
      assert new_ts[0] == 202.0
      assert new_ts[1] == 100.0
    end

    test "supports negative indices" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      {old, new_ts} = Access.get_and_update(ts, -1, fn val -> {val, val * 10} end)

      assert old == 100.0
      assert new_ts[-1] == 1000.0
    end

    test "raises for out of bounds index" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise ArgumentError, ~r/index 5 out of bounds/, fn ->
        Access.get_and_update(ts, 5, fn val -> {val, val * 2} end)
      end
    end

    test "raises when function returns :pop" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise ArgumentError, ~r/cannot pop from a TimeSeries/, fn ->
        Access.get_and_update(ts, 0, fn _ -> :pop end)
      end
    end

    test "works with update_in/3" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      new_ts = update_in(ts, [0], fn val -> val + 10 end)

      assert new_ts[0] == 111.0
      assert new_ts[1] == 100.0
    end
  end

  describe "Access.get_and_update/3 with DateTime" do
    test "updates value at datetime and returns {old_value, new_ts}" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      {old, new_ts} = Access.get_and_update(ts, dt1(), fn val -> {val, val * 2} end)

      assert old == 100.0
      assert new_ts[dt1()] == 200.0
      assert new_ts[dt2()] == 101.0
    end

    test "raises for non-existent datetime" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise ArgumentError, ~r/datetime .* not found/, fn ->
        Access.get_and_update(ts, dt2(), fn val -> {val, val * 2} end)
      end
    end

    test "raises when function returns :pop" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise ArgumentError, ~r/cannot pop from a TimeSeries/, fn ->
        Access.get_and_update(ts, dt1(), fn _ -> :pop end)
      end
    end

    test "works with update_in/3" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      new_ts = update_in(ts, [dt1()], fn val -> val + 50 end)

      assert new_ts[dt1()] == 150.0
      assert new_ts[dt2()] == 101.0
    end

    test "works with get_and_update_in/3" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      {old, new_ts} = get_and_update_in(ts, [dt2()], fn val -> {val * 10, val + 1} end)

      assert old == 1010.0
      assert new_ts[dt2()] == 102.0
    end
  end

  describe "Access.pop/2" do
    test "always raises error with index" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise RuntimeError, "you cannot pop a TimeSeries", fn ->
        Access.pop(ts, 0)
      end
    end

    test "always raises error with datetime" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise RuntimeError, "you cannot pop a TimeSeries", fn ->
        Access.pop(ts, dt1())
      end
    end
  end

  describe "Enumerable protocol - Enum.map/2" do
    test "maps over {datetime, value} tuples" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      result = Enum.map(ts, fn {_dt, value} -> value * 2 end)

      assert result == [204.0, 202.0, 200.0]
    end

    test "can access datetime in map" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      result = Enum.map(ts, fn {dt, _value} -> DateTime.to_unix(dt) end)

      assert result == [DateTime.to_unix(dt2()), DateTime.to_unix(dt1())]
    end

    test "maps empty TimeSeries returns empty list" do
      ts = TimeSeries.new()

      result = Enum.map(ts, fn {_dt, val} -> val * 2 end)

      assert result == []
    end
  end

  describe "Enumerable protocol - Enum.filter/2" do
    test "filters based on value" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      result = Enum.filter(ts, fn {_dt, value} -> value > 100.5 end)

      assert result == [{dt3(), 102.0}, {dt2(), 101.0}]
    end

    test "filters based on datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      result = Enum.filter(ts, fn {dt, _value} -> DateTime.compare(dt, dt2()) != :lt end)

      assert result == [{dt3(), 102.0}, {dt2(), 101.0}]
    end
  end

  describe "Enumerable protocol - Enum.reduce/3" do
    test "reduces to sum of values" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      result = Enum.reduce(ts, 0, fn {_dt, value}, acc -> value + acc end)

      assert result == 303.0
    end

    test "reduces empty TimeSeries returns accumulator" do
      ts = TimeSeries.new()

      result = Enum.reduce(ts, 42, fn {_dt, value}, acc -> value + acc end)

      assert result == 42
    end
  end

  describe "Enumerable protocol - Enum.count/1" do
    test "counts elements in TimeSeries" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert Enum.count(ts) == 3
    end

    test "counts empty TimeSeries" do
      ts = TimeSeries.new()

      assert Enum.count(ts) == 0
    end

    test "count is same as TimeSeries.size/1" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Enum.count(ts) == TimeSeries.size(ts)
    end
  end

  describe "Enumerable protocol - Enum.member?/2" do
    test "checks if datetime is member" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Enum.member?(ts, dt1()) == true
      assert Enum.member?(ts, dt2()) == true
    end

    test "returns false for non-existent datetime" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert Enum.member?(ts, dt2()) == false
      assert Enum.member?(ts, dt3()) == false
    end

    test "returns true regardless of value when datetime exists" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      # datetime exists, so member? returns true
      assert Enum.member?(ts, dt1()) == true
    end

    test "returns false for non-datetime elements" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert Enum.member?(ts, 100.0) == false
      assert Enum.member?(ts, "string") == false
      assert Enum.member?(ts, {dt1(), 100.0}) == false
    end
  end

  describe "Enumerable protocol - other Enum functions" do
    test "Enum.reverse/1" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      result = Enum.reverse(ts)

      assert result == [{dt1(), 100.0}, {dt2(), 101.0}, {dt3(), 102.0}]
    end

    test "Enum.any?/2" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Enum.any?(ts, fn {_dt, val} -> val > 100.5 end) == true
      assert Enum.any?(ts, fn {_dt, val} -> val > 200 end) == false
    end

    test "Enum.find/2" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert Enum.find(ts, fn {_dt, val} -> val > 100.5 end) == {dt3(), 102.0}
      assert Enum.find(ts, fn {_dt, val} -> val > 200 end) == nil
    end

    test "Enum.take/2" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)
        |> TimeSeries.add(dt4(), 103.0)

      result = Enum.take(ts, 2)

      assert result == [{dt4(), 103.0}, {dt3(), 102.0}]
    end
  end

  describe "integration scenarios" do
    test "add and update mixed usage" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.update(dt2(), 105.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert TimeSeries.size(ts) == 3
      assert ts[0] == 102.0
      assert ts[1] == 105.0
      assert ts[2] == 100.0
    end

    test "access by index and datetime together" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert ts[0] == 102.0
      assert ts[dt3()] == 102.0
      assert ts[1] == 101.0
      assert ts[dt2()] == 101.0
    end

    test "enumeration preserves chronological information" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      result = Enum.to_list(ts)

      assert result == [{dt3(), 102.0}, {dt2(), 101.0}, {dt1(), 100.0}]
    end
  end

  ## Private functions

  defp dt1, do: ~U[2024-01-01 10:00:00Z]
  defp dt2, do: ~U[2024-01-01 10:01:00Z]
  defp dt3, do: ~U[2024-01-01 10:02:00Z]
  defp dt4, do: ~U[2024-01-01 10:03:00Z]
  defp dt5, do: ~U[2024-01-01 10:04:00Z]
end
