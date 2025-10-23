defmodule TheoryCraft.Processors.IndicatorProcessorTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.{Bar, MarketEvent}
  alias TheoryCraft.Processors.IndicatorProcessor

  ## Mocks

  # Mock indicator that sends messages to test process to verify calls
  defmodule MockIndicator do
    alias TheoryCraft.IndicatorValue

    @behaviour TheoryCraft.Indicator

    @impl true
    def init(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      data_name = Keyword.fetch!(opts, :data)
      send(test_pid, {:init_called, opts})

      state = %{test_pid: test_pid, call_count: 0, data_name: data_name}
      {:ok, state}
    end

    @impl true
    def next(event, state) do
      %{test_pid: test_pid, call_count: call_count, data_name: data_name} = state

      send(test_pid, {:next_called, event, state})

      # Return the call count as the indicator value wrapped in IndicatorValue
      new_state = %{state | call_count: call_count + 1}

      indicator_value = %IndicatorValue{
        value: call_count,
        data_name: data_name
      }

      {:ok, indicator_value, new_state}
    end
  end

  # Mock indicator that fails on init
  defmodule FailingInitIndicator do
    @behaviour TheoryCraft.Indicator

    @impl true
    def init(_opts) do
      {:error, :init_failed}
    end

    @impl true
    def next(_event, _state), do: raise("Should not be called")
  end

  # Mock indicator that fails on next
  defmodule FailingNextIndicator do
    @behaviour TheoryCraft.Indicator

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def next(_event, _state) do
      {:error, :next_failed}
    end
  end

  ## Tests

  describe "init/1" do
    test "calls indicator module init with forwarded options" do
      opts = [module: MockIndicator, test_pid: self(), data: "test_data", name: "test_name"]

      assert {:ok, state} = IndicatorProcessor.init(opts)

      # Verify init was called with options (minus :module only)
      assert_received {:init_called, received_opts}
      assert Keyword.get(received_opts, :test_pid) == self()
      assert Keyword.get(received_opts, :data) == "test_data"
      assert Keyword.get(received_opts, :name) == "test_name"
      refute Keyword.has_key?(received_opts, :module)

      # Verify processor state structure
      assert %IndicatorProcessor{} = state
      assert state.module == MockIndicator
      assert state.state.test_pid == self()
      assert state.state.call_count == 0
    end

    test "raises error when module option is missing" do
      opts = [data: "bar", name: "test"]

      assert_raise ArgumentError, ~r/Missing required option: module/, fn ->
        IndicatorProcessor.init(opts)
      end
    end

    test "propagates indicator init errors" do
      opts = [module: FailingInitIndicator, data: "bar", name: "fail"]

      assert {:error, :init_failed} = IndicatorProcessor.init(opts)
    end
  end

  describe "next/2" do
    test "calls indicator module next with event and state" do
      {:ok, state} =
        IndicatorProcessor.init(
          module: MockIndicator,
          test_pid: self(),
          data: "bar",
          name: "mock_output"
        )

      bar = build_bar(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"bar" => bar}}

      assert {:ok, updated_event, new_state} = IndicatorProcessor.next(event, state)

      # Verify next was called with correct arguments
      assert_received {:next_called, received_event, received_state}
      assert received_event == event
      assert received_state.test_pid == self()
      assert received_state.call_count == 0

      # Verify the updated event contains indicator output wrapped in IndicatorValue
      assert %TheoryCraft.IndicatorValue{value: 0, data_name: "bar"} =
               updated_event.data["mock_output"]

      # Verify processor state was updated
      assert new_state.state.call_count == 1
    end

    test "maintains indicator state across multiple calls" do
      {:ok, state} =
        IndicatorProcessor.init(
          module: MockIndicator,
          test_pid: self(),
          data: "bar",
          name: "mock_output"
        )

      bar = build_bar(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"bar" => bar}}

      # First call
      {:ok, event1, state1} = IndicatorProcessor.next(event, state)
      assert %TheoryCraft.IndicatorValue{value: 0} = event1.data["mock_output"]
      assert state1.state.call_count == 1

      # Second call
      {:ok, event2, state2} = IndicatorProcessor.next(event, state1)
      assert %TheoryCraft.IndicatorValue{value: 1} = event2.data["mock_output"]
      assert state2.state.call_count == 2

      # Third call
      {:ok, event3, state3} = IndicatorProcessor.next(event, state2)
      assert %TheoryCraft.IndicatorValue{value: 2} = event3.data["mock_output"]
      assert state3.state.call_count == 3
    end

    test "propagates indicator next errors" do
      {:ok, state} =
        IndicatorProcessor.init(
          module: FailingNextIndicator,
          data: "bar",
          name: "fail"
        )

      bar = build_bar(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"bar" => bar}}

      assert {:error, :next_failed} = IndicatorProcessor.next(event, state)
    end

    test "returns updated event from indicator" do
      {:ok, state} =
        IndicatorProcessor.init(
          module: MockIndicator,
          test_pid: self(),
          data: "bar",
          name: "mock_output"
        )

      bar = build_bar(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"bar" => bar, "other" => 123}}

      {:ok, updated_event, _new_state} = IndicatorProcessor.next(event, state)

      # Original data should be preserved
      assert updated_event.data["bar"] == bar
      assert updated_event.data["other"] == 123
      # New data added by indicator (wrapped in IndicatorValue)
      assert %TheoryCraft.IndicatorValue{value: 0, data_name: "bar"} =
               updated_event.data["mock_output"]
    end
  end

  ## Private test helpers

  defp build_bar(time) do
    %Bar{
      time: time,
      open: 100.0,
      high: 100.0,
      low: 100.0,
      close: 100.0,
      volume: 1.0
    }
  end
end
