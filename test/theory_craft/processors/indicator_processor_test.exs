defmodule TheoryCraft.Processors.IndicatorProcessorTest do
  use ExUnit.Case, async: true

  alias TheoryCraft.{Candle, MarketEvent}
  alias TheoryCraft.Processors.IndicatorProcessor

  ## Mocks

  # Mock indicator that sends messages to test process to verify calls
  defmodule MockIndicator do
    @behaviour TheoryCraft.Indicator

    @impl true
    def init(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:init_called, opts})

      state = %{test_pid: test_pid, call_count: 0}
      {:ok, state}
    end

    @impl true
    def next(event, state) do
      %{test_pid: test_pid, call_count: call_count} = state
      send(test_pid, {:next_called, event, state})

      # Add a simple output to the event
      updated_event = put_in(event.data["mock_output"], call_count)
      new_state = %{state | call_count: call_count + 1}

      {:ok, updated_event, new_state}
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

      # Verify init was called with options (minus :module)
      assert_received {:init_called, received_opts}
      assert Keyword.get(received_opts, :test_pid) == self()
      assert Keyword.get(received_opts, :data) == "test_data"
      assert Keyword.get(received_opts, :name) == "test_name"
      refute Keyword.has_key?(received_opts, :module)

      # Verify processor state structure
      assert %IndicatorProcessor{} = state
      assert state.indicator_module == MockIndicator
      assert state.indicator_state.test_pid == self()
      assert state.indicator_state.call_count == 0
    end

    test "raises error when module option is missing" do
      opts = [data: "candle", name: "test"]

      assert_raise ArgumentError, ~r/Missing required option: module/, fn ->
        IndicatorProcessor.init(opts)
      end
    end

    test "propagates indicator init errors" do
      opts = [module: FailingInitIndicator, data: "candle", name: "fail"]

      assert {:error, :init_failed} = IndicatorProcessor.init(opts)
    end
  end

  describe "next/2" do
    test "calls indicator module next with event and state" do
      {:ok, state} = IndicatorProcessor.init(module: MockIndicator, test_pid: self())

      candle = build_candle(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"candle" => candle}}

      assert {:ok, updated_event, new_state} = IndicatorProcessor.next(event, state)

      # Verify next was called with correct arguments
      assert_received {:next_called, received_event, received_state}
      assert received_event == event
      assert received_state.test_pid == self()
      assert received_state.call_count == 0

      # Verify the updated event contains indicator output
      assert updated_event.data["mock_output"] == 0

      # Verify processor state was updated
      assert new_state.indicator_state.call_count == 1
    end

    test "maintains indicator state across multiple calls" do
      {:ok, state} = IndicatorProcessor.init(module: MockIndicator, test_pid: self())

      candle = build_candle(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"candle" => candle}}

      # First call
      {:ok, event1, state1} = IndicatorProcessor.next(event, state)
      assert event1.data["mock_output"] == 0
      assert state1.indicator_state.call_count == 1

      # Second call
      {:ok, event2, state2} = IndicatorProcessor.next(event, state1)
      assert event2.data["mock_output"] == 1
      assert state2.indicator_state.call_count == 2

      # Third call
      {:ok, event3, state3} = IndicatorProcessor.next(event, state2)
      assert event3.data["mock_output"] == 2
      assert state3.indicator_state.call_count == 3
    end

    test "propagates indicator next errors" do
      {:ok, state} = IndicatorProcessor.init(module: FailingNextIndicator)

      candle = build_candle(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"candle" => candle}}

      assert {:error, :next_failed} = IndicatorProcessor.next(event, state)
    end

    test "returns updated event from indicator" do
      {:ok, state} = IndicatorProcessor.init(module: MockIndicator, test_pid: self())

      candle = build_candle(~U[2024-01-01 10:00:00Z])
      event = %MarketEvent{data: %{"candle" => candle, "other" => 123}}

      {:ok, updated_event, _new_state} = IndicatorProcessor.next(event, state)

      # Original data should be preserved
      assert updated_event.data["candle"] == candle
      assert updated_event.data["other"] == 123
      # New data added by indicator
      assert updated_event.data["mock_output"] == 0
    end
  end

  ## Private test helpers

  defp build_candle(time) do
    %Candle{
      time: time,
      open: 100.0,
      high: 100.0,
      low: 100.0,
      close: 100.0,
      volume: 1.0
    }
  end
end
