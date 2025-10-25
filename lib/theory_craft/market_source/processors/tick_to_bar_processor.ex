defmodule TheoryCraft.MarketSource.Processors.TickToBarProcessor do
  @moduledoc """
  Transforms tick data into bar data with configurable timeframes.

  This processor converts a stream of `Tick` structs into `Bar` structs (OHLCV data)
  by resampling at specified timeframe intervals. It supports all standard trading timeframes
  from tick-based to monthly bars.

  ## Supported Timeframes

  - **Tick-based** (`t<N>`): Group N ticks into one bar (e.g., "t5" = 5 ticks per bar)
  - **Second-based** (`s<N>`): N-second bars (e.g., "s5", "s30")
  - **Minute-based** (`m<N>`): N-minute bars (e.g., "m1", "m5", "m15")
  - **Hour-based** (`h<N>`): N-hour bars (e.g., "h1", "h4")
  - **Daily** (`D<N>`): N-day bars (e.g., "D", "D3")
  - **Weekly** (`W<N>`): N-week bars (e.g., "W", "W2")
  - **Monthly** (`M<N>`): N-month bars (e.g., "M", "M3")

  ## Options

  - `:data` (required) - Name of the data stream in the MarketEvent
  - `:timeframe` (required) - Timeframe string (e.g., "m5", "h1", "D")
  - `:name` - Custom name for this processor (default: "<data>_<timeframe>")
  - `:price_type` - Price to use from ticks: `:mid`, `:bid`, or `:ask` (default: `:mid`)
  - `:fake_volume?` - Use fake volume of 1.0 per tick when volume is missing (default: `true`)
  - `:market_open` - Time when the market opens, used for daily/weekly/monthly alignment (default: `~T[00:00:00]`)
  - `:weekly_open` - Day the week starts (default: `:monday`)

  ## Alignment Rules

  - **Tick-based**: No alignment, starts with first tick
  - **Second/Minute/Hour**: Aligns to the timeframe boundary (e.g., m5 aligns to 10:00, 10:05, 10:10...)
  - **Daily**: Aligns to `market_open` time each day
  - **Weekly**: Aligns to `weekly_open` day + `market_open` time
  - **Monthly**: Aligns to first day of month + `market_open` time

  ## Examples

      # 5-minute bars with mid price
      opts = [data: "eurusd", timeframe: "m5"]
      {:ok, state} = TickToBarProcessor.init(opts)

      # Daily bars with bid price, market opens at 9:30
      opts = [
        data: "xauusd",
        timeframe: "D",
        price_type: :bid,
        market_open: ~T[09:30:00]
      ]
      {:ok, state} = TickToBarProcessor.init(opts)

      # Weekly bars starting on Sunday
      opts = [
        data: "btcusd",
        timeframe: "W",
        weekly_open: :sunday
      ]
      {:ok, state} = TickToBarProcessor.init(opts)

  """

  alias __MODULE__
  alias TheoryCraft.MarketSource.{Bar, Tick}
  alias TheoryCraft.MarketSource.MarketEvent
  alias TheoryCraft.TimeFrame
  alias TheoryCraft.Utils

  @behaviour TheoryCraft.MarketSource.Processor

  @typedoc """
  The processor state containing configuration and current bar information.
  """
  @type t :: %__MODULE__{
          name: String.t(),
          data_name: String.t(),
          market_open: Time.t(),
          weekly_open:
            :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday,
          timeframe: TimeFrame.t(),
          current_bar: Bar.t() | nil,
          next_time: DateTime.t() | nil,
          tick_counter: non_neg_integer() | nil,
          price_type: :mid | :bid | :ask,
          fake_volume?: boolean()
        }

  defstruct name: nil,
            data_name: nil,
            market_open: nil,
            weekly_open: nil,
            timeframe: nil,
            current_bar: nil,
            # Used to track the next bar's opening time (only for bars)
            next_time: nil,
            # Used to count the number of ticks received (only for tick timeframe)
            tick_counter: nil,
            # Used to track the price type for Tick data (mid, bid, ask)
            price_type: nil,
            # If volume is missing in Tick data, use fake volume of 1 per tick
            fake_volume?: true

  ## Processor behaviour

  @doc """
  Initializes the processor with the given options.

  ## Options

  - `:data` (required) - Name of the data stream in the MarketEvent
  - `:timeframe` (required) - Timeframe string (e.g., "m5", "h1", "D")
  - `:name` - Custom name for this processor (default: "<data>_<timeframe>")
  - `:price_type` - Price to use: `:mid`, `:bid`, or `:ask` (default: `:mid`)
  - `:fake_volume?` - Use fake volume when missing (default: `true`)
  - `:market_open` - Market open time (default: `~T[00:00:00]`)
  - `:weekly_open` - Week start day: `:monday` or `:sunday` (default: `:monday`)

  ## Examples

      iex> TickToBarProcessor.init(data: "eurusd", timeframe: "m5")
      {:ok, %TickToBarProcessor{data_name: "eurusd", timeframe: {"m", 5}, ...}}

      iex> TickToBarProcessor.init(data: "xauusd", timeframe: "D", price_type: :bid)
      {:ok, %TickToBarProcessor{data_name: "xauusd", price_type: :bid, ...}}

  """
  @impl true
  @spec init(Keyword.t()) :: {:ok, t()}
  def init(opts) do
    data_name = Utils.required_opt!(opts, :data)
    timeframe_from_user = Utils.required_opt!(opts, :timeframe)
    name = Keyword.get(opts, :name, "#{data_name}_#{timeframe_from_user}")
    price_type = Keyword.get(opts, :price_type, :mid)
    fake_volume? = Keyword.get(opts, :fake_volume?, true)

    market_open = opts |> Keyword.get(:market_open, ~T[00:00:00]) |> Time.truncate(:second)
    weekly_open = Keyword.get(opts, :weekly_open, :monday)
    timeframe = TimeFrame.parse!(timeframe_from_user)

    state = %TickToBarProcessor{
      name: name,
      data_name: data_name,
      market_open: market_open,
      weekly_open: weekly_open,
      timeframe: timeframe,
      price_type: price_type,
      fake_volume?: fake_volume?
    }

    {:ok, state}
  end

  @doc """
  Processes a MarketEvent containing Tick data and transforms it into Bar data.

  This function handles the transformation based on the configured timeframe:

  - **Tick-based timeframes** (`t<N>`): Accumulates N ticks before creating a new bar.
    Also handles market_open transitions by starting a new bar when crossing market open time.

  - **Time-based timeframes** (`s`, `m`, `h`, `D`, `W`, `M`): Creates bars aligned to
    timeframe boundaries. Starts a new bar when the tick's time crosses the `next_time`.

  The function reads Tick data from the `:data` key in the MarketEvent and writes the generated
  Bar data to the `:name` key. This allows the input ticks and output bars to coexist in
  the event's data map. If `:name` equals `:data`, the ticks will be overwritten by the bars.

  ## Behavior

  - **First tick**: Creates the initial bar with OHLC all set to the tick's price
  - **Within period**: Updates the current bar's high, low, close, and volume
  - **Period boundary**: Creates a new bar and resets accumulation

  ## Examples

      # Processing first tick (5-minute timeframe)
      # By default, name is "eurusd_m5" when data is "eurusd"
      event = %MarketEvent{data: %{"eurusd" => %Tick{time: ~U[2024-01-15 10:07:30Z], bid: 1.0850, ask: 1.0852}}}
      {:ok, state} = TickToBarProcessor.init(data: "eurusd", timeframe: "m5")
      {:ok, new_event, new_state} = TickToBarProcessor.next(event, state)
      # new_event.data["eurusd_m5"] is a Bar at time 10:05:00 with OHLC = 1.0851
      # new_event.data["eurusd"] still contains the original Tick

      # Processing tick within same period
      event2 = %MarketEvent{data: %{"eurusd" => %Tick{time: ~U[2024-01-15 10:08:00Z], bid: 1.0855, ask: 1.0857}}}
      {:ok, new_event2, new_state2} = TickToBarProcessor.next(event2, new_state)
      # new_event2.data["eurusd_m5"] updates the same bar with new high/close

      # Crossing boundary creates new bar
      event3 = %MarketEvent{data: %{"eurusd" => %Tick{time: ~U[2024-01-15 10:10:00Z], bid: 1.0860, ask: 1.0862}}}
      {:ok, new_event3, new_state3} = TickToBarProcessor.next(event3, new_state2)
      # new_event3.data["eurusd_m5"] is a NEW Bar at time 10:10:00

      # Using explicit name to preserve both ticks and bars
      {:ok, state} = TickToBarProcessor.init(data: "xauusd_ticks", timeframe: "h1", name: "xauusd_h1")
      # Input: event.data["xauusd_ticks"] contains Tick
      # Output: event.data["xauusd_h1"] will contain Bar
      # Both coexist in the same MarketEvent

  """
  @impl true
  @spec next(MarketEvent.t(), t()) :: {:ok, MarketEvent.t(), t()}
  def next(event, %TickToBarProcessor{timeframe: {"t", _mult}, tick_counter: nil} = state) do
    %TickToBarProcessor{
      name: name,
      data_name: data_name,
      price_type: price_type,
      fake_volume?: fake_volume?
    } = state

    tick = market_data_tick!(event, data_name)
    # First tick is always a new bar and not a new market
    bar = create_bar_from_tick(tick.time, tick, price_type, fake_volume?, false)

    updated_event = %MarketEvent{event | data: Map.put(event.data, name, bar)}
    updated_state = %TickToBarProcessor{state | tick_counter: 1, current_bar: bar}

    {:ok, updated_event, updated_state}
  end

  @impl true
  def next(event, %TickToBarProcessor{timeframe: {"t", _mult}} = state) do
    %TickToBarProcessor{
      name: name,
      data_name: data_name,
      price_type: price_type,
      current_bar: current_bar,
      fake_volume?: fake_volume?,
      tick_counter: tick_counter
    } = state

    tick = market_data_tick!(event, data_name)
    new_bar? = new_bar?(tick, state)
    new_market? = if new_bar?, do: new_market?(tick, state), else: false

    bar =
      case new_bar? do
        true -> create_bar_from_tick(tick.time, tick, price_type, fake_volume?, new_market?)
        false -> update_bar_from_tick(current_bar, tick, price_type, fake_volume?)
      end

    updated_event = %MarketEvent{event | data: Map.put(event.data, name, bar)}

    updated_state = %TickToBarProcessor{
      state
      | tick_counter: if(new_bar?, do: 1, else: tick_counter + 1),
        current_bar: bar
    }

    {:ok, updated_event, updated_state}
  end

  # First tick for time-based timeframe (s, m, h, D, W, M)
  @impl true
  def next(event, %TickToBarProcessor{timeframe: {unit, _mult}, next_time: nil} = state)
      when unit in ["s", "m", "h", "D", "W", "M"] do
    %TickToBarProcessor{
      name: name,
      data_name: data_name,
      price_type: price_type,
      fake_volume?: fake_volume?,
      timeframe: timeframe,
      market_open: market_open
    } = state

    tick = market_data_tick!(event, data_name)
    aligned_time = align_time(tick.time, timeframe, state)

    # First tick is always a new bar and not a new market
    bar = create_bar_from_tick(aligned_time, tick, price_type, fake_volume?, false)

    next_time = calculate_next_bar_time(aligned_time, timeframe, market_open)

    updated_event = %MarketEvent{event | data: Map.put(event.data, name, bar)}
    updated_state = %TickToBarProcessor{state | next_time: next_time, current_bar: bar}

    {:ok, updated_event, updated_state}
  end

  # Subsequent ticks for time-based timeframe (s, m, h, D, W, M)
  @impl true
  def next(event, %TickToBarProcessor{timeframe: {unit, _mult}} = state)
      when unit in ["s", "m", "h", "D", "W", "M"] do
    %TickToBarProcessor{
      name: name,
      data_name: data_name,
      price_type: price_type,
      current_bar: current_bar,
      fake_volume?: fake_volume?,
      timeframe: timeframe,
      market_open: market_open
    } = state

    tick = market_data_tick!(event, data_name)
    new_bar? = new_bar?(tick, state)
    new_market? = if new_bar?, do: new_market?(tick, state), else: false

    {bar, next_time} =
      case new_bar? do
        true ->
          aligned_time = align_time(tick.time, timeframe, state)

          new_bar =
            create_bar_from_tick(aligned_time, tick, price_type, fake_volume?, new_market?)

          next_time = calculate_next_bar_time(aligned_time, timeframe, market_open)

          {new_bar, next_time}

        false ->
          updated_bar = update_bar_from_tick(current_bar, tick, price_type, fake_volume?)
          {updated_bar, state.next_time}
      end

    updated_event = %MarketEvent{event | data: Map.put(event.data, name, bar)}
    updated_state = %TickToBarProcessor{state | next_time: next_time, current_bar: bar}

    {:ok, updated_event, updated_state}
  end

  ## Private functions

  defp tick_price(%Tick{ask: ask}, :ask), do: ask
  defp tick_price(%Tick{bid: bid}, :bid), do: bid

  defp tick_price(%Tick{ask: ask, bid: bid}, :mid) do
    case {ask, bid} do
      {nil, nil} -> raise "Both ask and bid can't be nil"
      {ask, nil} -> ask
      {nil, bid} -> bid
      {ask, bid} -> (ask + bid) / 2
    end
  end

  defp volume(%Tick{ask_volume: ask_volume, bid_volume: bid_volume}, fake_volume?) do
    case {ask_volume, bid_volume} do
      {nil, nil} -> if fake_volume?, do: 1.0, else: nil
      {ask_volume, nil} -> ask_volume
      {nil, bid_volume} -> bid_volume
      {ask_volume, bid_volume} -> ask_volume + bid_volume
    end
  end

  defp market_data_tick!(event, name) do
    case event do
      %MarketEvent{data: %{^name => %Tick{} = tick}} -> tick
      %MarketEvent{data: %{^name => value}} -> raise "Data must be Tick, got #{inspect(value)}"
    end
  end

  # Tick-based timeframe
  defp new_bar?(%Tick{} = tick, %TickToBarProcessor{timeframe: {"t", mult}} = state) do
    %Tick{time: time} = tick

    %TickToBarProcessor{
      tick_counter: counter,
      market_open: market_open,
      current_bar: %Bar{time: bar_dt}
    } = state

    bar_time = DateTime.to_time(bar_dt)
    tick_time = DateTime.to_time(time)

    cond do
      counter >= mult ->
        true

      Time.compare(bar_time, market_open) == :lt and
          Time.compare(tick_time, market_open) != :lt ->
        true

      true ->
        false
    end
  end

  # Time-based timeframe (s, m, h, D, W, M)
  defp new_bar?(%Tick{time: time}, %TickToBarProcessor{next_time: next_time}) do
    DateTime.compare(time, next_time) != :lt
  end

  # Check if tick crosses market_open boundary
  defp new_market?(
         %Tick{time: tick_time},
         %TickToBarProcessor{
           market_open: market_open,
           current_bar: %Bar{time: bar_dt}
         }
       ) do
    bar_time = DateTime.to_time(bar_dt)
    tick_time_only = DateTime.to_time(tick_time)

    Time.compare(bar_time, market_open) == :lt and
      Time.compare(tick_time_only, market_open) != :lt
  end

  # Align a DateTime to the start of the timeframe period
  defp align_time(datetime, {"s", mult}, _state) do
    %DateTime{microsecond: {_value, precision}, second: second} = datetime
    aligned_second = second - rem(second, mult)
    %DateTime{datetime | second: aligned_second, microsecond: {0, precision}}
  end

  defp align_time(datetime, {"m", mult}, _state) do
    %DateTime{microsecond: {_value, precision}, minute: minute} = datetime
    aligned_minute = minute - rem(minute, mult)
    %DateTime{datetime | minute: aligned_minute, second: 0, microsecond: {0, precision}}
  end

  defp align_time(datetime, {"h", mult}, _state) do
    %DateTime{microsecond: {_value, precision}, hour: hour} = datetime
    aligned_hour = hour - rem(hour, mult)
    %DateTime{datetime | hour: aligned_hour, minute: 0, second: 0, microsecond: {0, precision}}
  end

  defp align_time(datetime, {"D", _mult}, %{market_open: market_open}) do
    %DateTime{microsecond: {_value, precision}, time_zone: time_zone} = datetime
    date = DateTime.to_date(datetime)

    {:ok, naive} = NaiveDateTime.new(date, market_open)
    result = DateTime.from_naive!(naive, time_zone)

    %DateTime{result | microsecond: {0, precision}}
  end

  defp align_time(datetime, {"W", _mult}, %{market_open: market_open, weekly_open: weekly_open}) do
    %DateTime{microsecond: {_value, precision}, time_zone: time_zone} = datetime
    date = DateTime.to_date(datetime)
    start_of_week = Date.beginning_of_week(date, weekly_open)

    {:ok, naive} = NaiveDateTime.new(start_of_week, market_open)
    result = DateTime.from_naive!(naive, time_zone)

    %DateTime{result | microsecond: {0, precision}}
  end

  defp align_time(datetime, {"M", _mult}, %{market_open: market_open}) do
    %DateTime{microsecond: {_value, precision}, time_zone: time_zone} = datetime
    date = DateTime.to_date(datetime)
    first_of_month = %Date{date | day: 1}

    {:ok, naive} = NaiveDateTime.new(first_of_month, market_open)
    result = DateTime.from_naive!(naive, time_zone)

    %DateTime{result | microsecond: {0, precision}}
  end

  # Add a timeframe period to a DateTime
  defp add_timeframe(datetime, {"s", mult}), do: DateTime.add(datetime, mult, :second)
  defp add_timeframe(datetime, {"m", mult}), do: DateTime.add(datetime, mult, :minute)
  defp add_timeframe(datetime, {"h", mult}), do: DateTime.add(datetime, mult, :hour)

  defp add_timeframe(datetime, {"D", mult}) do
    %DateTime{
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      microsecond: microsecond,
      time_zone: time_zone
    } = datetime

    date = Date.new!(year, month, day)
    new_date = Date.add(date, mult)

    {:ok, time} = Time.new(hour, minute, second, microsecond)
    {:ok, naive} = NaiveDateTime.new(new_date, time)

    DateTime.from_naive!(naive, time_zone)
  end

  defp add_timeframe(datetime, {"W", mult}) do
    %DateTime{
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      microsecond: microsecond,
      time_zone: time_zone
    } = datetime

    date = Date.new!(year, month, day)
    new_date = Date.add(date, mult * 7)

    {:ok, time} = Time.new(hour, minute, second, microsecond)
    {:ok, naive} = NaiveDateTime.new(new_date, time)

    DateTime.from_naive!(naive, time_zone)
  end

  defp add_timeframe(datetime, {"M", mult}) do
    %DateTime{
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      microsecond: microsecond,
      time_zone: time_zone
    } = datetime

    # Handle year overflow when adding months (e.g., month 15 becomes year+1, month 3)
    new_month = month + mult

    {new_year, final_month} =
      if new_month > 12 do
        years_to_add = div(new_month - 1, 12)
        {year + years_to_add, rem(new_month - 1, 12) + 1}
      else
        {year, new_month}
      end

    # Adjust day if it doesn't exist in new month (e.g., Jan 31 -> Feb 28/29)
    days_in_new_month = Date.days_in_month(Date.new!(new_year, final_month, 1))
    final_day = min(day, days_in_new_month)

    new_date = Date.new!(new_year, final_month, final_day)
    {:ok, time} = Time.new(hour, minute, second, microsecond)
    {:ok, naive} = NaiveDateTime.new(new_date, time)

    DateTime.from_naive!(naive, time_zone)
  end

  # Calculate the next DateTime where time equals market_open
  defp next_market_open_datetime(current_datetime, market_open_time) do
    %DateTime{time_zone: time_zone, microsecond: {_value, precision}} = current_datetime

    current_time = DateTime.to_time(current_datetime)
    date = DateTime.to_date(current_datetime)

    # If current time is before market_open, next market_open is today
    # Otherwise, it's tomorrow
    target_date =
      case Time.compare(current_time, market_open_time) do
        :lt -> date
        _ -> Date.add(date, 1)
      end

    {:ok, naive} = NaiveDateTime.new(target_date, market_open_time)
    result = DateTime.from_naive!(naive, time_zone)

    %DateTime{result | microsecond: {0, precision}}
  end

  # Calculate next_time considering both timeframe and market_open
  # Returns the earlier of: (current_time + timeframe) or next_market_open
  defp calculate_next_time(current_time, timeframe, market_open) do
    normal_next = add_timeframe(current_time, timeframe)
    next_mo = next_market_open_datetime(current_time, market_open)

    case DateTime.compare(next_mo, normal_next) do
      :lt -> next_mo
      _ -> normal_next
    end
  end

  # Calculate next bar time
  # For intra-day timeframes (s/m/h), considers market_open
  # For D/W/M, market_open is already part of alignment
  defp calculate_next_bar_time(aligned_time, timeframe, market_open) do
    case timeframe do
      {unit, _mult} when unit in ["s", "m", "h"] ->
        calculate_next_time(aligned_time, timeframe, market_open)

      _ ->
        add_timeframe(aligned_time, timeframe)
    end
  end

  defp create_bar_from_tick(time, tick, price_type, fake_volume?, new_market?) do
    price = tick_price(tick, price_type)
    volume = volume(tick, fake_volume?)

    %Bar{
      time: time,
      open: price,
      high: price,
      low: price,
      close: price,
      volume: volume,
      new_bar?: true,
      new_market?: new_market?
    }
  end

  defp update_bar_from_tick(bar, tick, price_type, fake_volume?) do
    %Bar{volume: prev_volume, high: high, low: low} = bar

    price = tick_price(tick, price_type)
    volume = volume(tick, fake_volume?)

    final_volume =
      case {prev_volume, volume} do
        {nil, nil} -> nil
        {nil, volume} -> volume
        {prev_volume, nil} -> prev_volume
        {prev_volume, volume} -> prev_volume + volume
      end

    %Bar{
      bar
      | high: max(high, price),
        low: min(low, price),
        close: price,
        volume: final_volume,
        new_bar?: false,
        new_market?: false
    }
  end
end
