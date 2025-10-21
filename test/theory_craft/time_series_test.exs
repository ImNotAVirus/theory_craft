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

  describe "at/2" do
    test "returns value at valid integer index" do
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
  end

  describe "replace_at/3" do
    test "replaces value at integer index" do
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

    test "replaces value at negative index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      new_ts = TimeSeries.replace_at(ts, -1, 999.0)

      assert new_ts[-1] == 999.0
      assert new_ts[0] == 101.0
    end

    test "returns original series if integer index out of bounds" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      new_ts = TimeSeries.replace_at(ts, 5, 999.0)

      assert new_ts == ts
      assert new_ts[0] == 100.0
    end

    test "replaces value at datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      new_ts = TimeSeries.replace_at(ts, dt2(), 999.0)

      assert new_ts[dt2()] == 999.0
      assert new_ts[dt1()] == 100.0
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

  describe "Access protocol" do
    test "bracket syntax works with integer index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert ts[0] == 102.0
      assert ts[1] == 101.0
      assert ts[2] == 100.0
      assert ts[3] == nil
    end

    test "bracket syntax works with negative indices" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert ts[-1] == 100.0
      assert ts[-2] == 101.0
      assert ts[-3] == 102.0
      assert ts[-4] == nil
    end

    test "bracket syntax works with datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert ts[dt1()] == 100.0
      assert ts[dt2()] == 101.0
      assert ts[dt3()] == 102.0
      assert ts[dt4()] == nil
    end

    test "fetches value at valid integer index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Access.fetch(ts, 0) == {:ok, 101.0}
      assert Access.fetch(ts, 1) == {:ok, 100.0}
    end

    test "fetches value at datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Access.fetch(ts, dt1()) == {:ok, 100.0}
      assert Access.fetch(ts, dt2()) == {:ok, 101.0}
    end

    test "returns :error for out of bounds or non-existent key" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert Access.fetch(ts, 10) == :error
      assert Access.fetch(ts, dt2()) == :error
    end

    test "fetches slice with range" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      assert Access.fetch(ts, 0..1) == {:ok, [102.0, 101.0]}
    end

    test "get_and_update updates value at integer index" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      {old_value, new_ts} = Access.get_and_update(ts, 0, fn val -> {val, val * 2} end)

      assert old_value == 101.0
      assert new_ts[0] == 202.0
      assert new_ts[1] == 100.0
    end

    test "get_and_update updates value at datetime" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      {old_value, new_ts} = Access.get_and_update(ts, dt1(), fn val -> {val, val * 2} end)

      assert old_value == 100.0
      assert new_ts[dt1()] == 200.0
      assert new_ts[dt2()] == 101.0
    end

    test "pop always raises error" do
      ts = TimeSeries.new() |> TimeSeries.add(dt1(), 100.0)

      assert_raise RuntimeError, "you cannot pop a TimeSeries", fn ->
        Access.pop(ts, 0)
      end
    end
  end

  describe "Enumerable protocol" do
    test "Enum.count matches TimeSeries.size" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)

      assert Enum.count(ts) == TimeSeries.size(ts)
    end

    test "enumerates as {datetime, value} tuples" do
      ts =
        TimeSeries.new()
        |> TimeSeries.add(dt1(), 100.0)
        |> TimeSeries.add(dt2(), 101.0)
        |> TimeSeries.add(dt3(), 102.0)

      result = Enum.to_list(ts)

      assert result == [{dt3(), 102.0}, {dt2(), 101.0}, {dt1(), 100.0}]
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
  end

  ## Private functions

  defp dt1, do: ~U[2024-01-01 10:00:00Z]
  defp dt2, do: ~U[2024-01-01 10:01:00Z]
  defp dt3, do: ~U[2024-01-01 10:02:00Z]
  defp dt4, do: ~U[2024-01-01 10:03:00Z]
  defp dt5, do: ~U[2024-01-01 10:04:00Z]
end
