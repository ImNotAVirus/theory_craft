# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TheoryCraft is an Elixir library for backtesting trading strategies using market data. It provides a streaming-based architecture for processing ticks and candles through configurable processors and data feeds.

## Common Commands

### Testing
```bash
# Run all tests
mix test

# Run a specific test file
mix test test/theory_craft/memory_data_feed_test.exs

# Run tests with specific line number
mix test test/theory_craft/memory_data_feed_test.exs:10
```

### Development
```bash
# Compile the project
mix compile

# Format code
mix format

# Run in interactive shell
iex -S mix
```

## Architecture

### Core Data Flow

The library uses a **streaming pipeline architecture** where market data flows through processors:

1. **Data Source** → 2. **DataFeed** → 3. **MarketEvent Stream** → 4. **Processors** → 5. **Strategy/Output**

### Key Concepts

#### DataFeed Behaviour
- Defines the contract for data sources (lib/theory_craft/data_feed.ex)
- Implementations must provide `stream/1` and `stream!/1` functions
- Returns `Enumerable.t(Tick.t() | Candle.t())`
- Current implementations:
  - `MemoryDataFeed`: In-memory ETS-based storage for tick/candle data
  - `TicksCSVDataFeed`: Reads tick data from CSV files

#### MarketEvent
- Wrapper struct that flows through the processing pipeline (lib/theory_craft/market_event.ex)
- Contains a `data` map where keys are data stream names and values are Tick/Candle structs
- Allows multiple data streams to be tracked simultaneously in the future

#### Processor Behaviour
- Transforms MarketEvents (lib/theory_craft/processor.ex)
- Implements stateful stream processing with `init/1` and `next/2` callbacks
- Example: `TickToCandleProcessor` resamples tick data into candles at specified timeframes

#### MarketSimulator
- Main orchestration module (lib/theory_craft/market_simulator.ex)
- Fluent API for building backtesting pipelines:
  ```elixir
  %MarketSimulator{}
  |> add_data(stream, name: "xauusd_ticks")
  |> resample("m5")  # Resample to 5-minute candles
  |> stream()
  ```
- Currently supports one data feed at a time (will support multiple in future)
- Uses `Stream.transform/3` to apply processors to the data flow

### Data Structures

#### Tick (lib/theory_craft/tick.ex)
- Represents a single market tick
- Fields: `time`, `ask`, `bid`, `ask_volume`, `bid_volume`

#### Candle (lib/theory_craft/candle.ex)
- Represents OHLC candle data
- Fields: `time`, `open`, `high`, `low`, `close`, `volume`

#### TimeFrame (lib/theory_craft/time_frame.ex)
- Parses timeframe strings like "m5" (5 minutes), "h1" (1 hour), "D" (daily)
- Supported units: t (tick), s (second), m (minute), h (hour), D (day), W (week), M (month)
- Format: `<unit><multiplier>` (e.g., "m15" = 15 minutes)

### Important Implementation Details

#### MemoryDataFeed
- Uses ETS ordered_set for efficient time-ordered data storage
- Supports automatic precision detection (second/millisecond/microsecond)
- Stores data in compressed format using tuples instead of structs
- Use `close/1` to clean up ETS tables when done

#### TickToCandleProcessor
- Handles tick-to-candle resampling with configurable timeframes
- Supports `price_type` option: `:mid`, `:bid`, or `:ask`
- Supports `fake_volume?` option to generate volume of 1.0 per tick when volume data is missing
- Manages `market_open` time to handle day transitions correctly for tick-based timeframes

## File Organization

```
lib/theory_craft/
├── data_feed.ex                  # DataFeed behaviour
├── processor.ex                  # Processor behaviour
├── market_simulator.ex           # Main orchestration
├── market_event.ex               # Event wrapper
├── tick.ex                       # Tick data structure
├── candle.ex                     # Candle data structure
├── time_frame.ex                 # TimeFrame parsing
├── data_feeds/
│   ├── memory_data_feed.ex      # ETS-based in-memory feed
│   └── ticks_csv_data_feed.ex   # CSV file reader
└── processors/
    └── tick_to_candle_processor.ex  # Tick resampling
```

## Coding Guidelines

### Elixir Best Practices

#### DateTime and Struct Manipulation

1. **Preserve microsecond precision dynamically**
   - Never hardcode microsecond precision (e.g., `{0, 6}`)
   - Always extract and preserve the precision from the input datetime
   - Example:
     ```elixir
     # ❌ Bad - hardcoded precision
     %DateTime{datetime | second: new_second, microsecond: {0, 6}}

     # ✅ Good - preserve input precision
     %DateTime{microsecond: {_value, precision}} = datetime
     %DateTime{datetime | second: new_second, microsecond: {0, precision}}
     ```

2. **Use explicit struct types for updates**
   - Always specify the struct type when updating fields
   - Never use generic map syntax `%{...}` for struct updates
   - Example:
     ```elixir
     # ❌ Bad - generic map update
     %{datetime | hour: new_hour}
     %{date | day: 1}

     # ✅ Good - explicit struct type
     %DateTime{datetime | hour: new_hour}
     %Date{date | day: 1}
     ```

3. **Use pattern matching for multiple field access**
   - When a function uses multiple fields from the same struct, use pattern matching instead of dot access
   - This makes the code more explicit about which fields are being used
   - Example:
     ```elixir
     # ❌ Bad - multiple dot accesses
     defp process_datetime(datetime) do
       year = datetime.year
       month = datetime.month
       day = datetime.day
       # ...
     end

     # ✅ Good - pattern matching in function body
     defp process_datetime(datetime) do
       %DateTime{year: year, month: month, day: day} = datetime
       # ...
     end
     ```

4. **Pattern match only execution flow fields in function headers**
   - In function headers, only pattern match fields needed for execution flow (guards, clause dispatch)
   - Pattern match other fields inside the function body
   - This keeps function signatures focused on what determines execution path
   - Example:
     ```elixir
     # ❌ Bad - pattern matching all fields in header
     def function(%Structure{field1: field1, field2: field2, field3: :toto} = struct)
         when field2 in [1, 2, 3] do
       # field1 is only used in body, not in guard
       # ...
     end

     # ✅ Good - only flow-critical fields in header
     def function(%Structure{field2: field2, field3: :toto} = struct)
         when field2 in [1, 2, 3] do
       # Pattern match other fields in body when needed
       %Structure{field1: field1} = struct
       # ...
     end
     ```

5. **Add blank line before return value in functions with more than 3 lines**
   - If a function has more than 3 lines and returns a value, add a blank line before the return
   - This visually separates the function logic from its result
   - Example:
     ```elixir
     # ❌ Bad - no blank line before return
     defp align_time(datetime, {"M", _mult}, %{market_open: market_open}) do
       %DateTime{microsecond: {_value, precision}, time_zone: time_zone} = datetime
       date = DateTime.to_date(datetime)
       first_of_month = %Date{date | day: 1}
       {:ok, naive} = NaiveDateTime.new(first_of_month, market_open)
       result = DateTime.from_naive!(naive, time_zone)
       %DateTime{result | microsecond: {0, precision}}
     end

     # ✅ Good - blank line before return
     defp align_time(datetime, {"M", _mult}, %{market_open: market_open}) do
       %DateTime{microsecond: {_value, precision}, time_zone: time_zone} = datetime
       date = DateTime.to_date(datetime)
       first_of_month = %Date{date | day: 1}
       {:ok, naive} = NaiveDateTime.new(first_of_month, market_open)
       result = DateTime.from_naive!(naive, time_zone)

       %DateTime{result | microsecond: {0, precision}}
     end
     ```

6. **Separate logical blocks with blank lines**
   - Avoid large blocks of code without visual separation
   - Group related operations and separate them with blank lines
   - Typical grouping: variable extraction → computation → result
   - Example:
     ```elixir
     # ❌ Bad - no logical separation
     defp add_timeframe(datetime, {"M", mult}) do
       %DateTime{year: year, month: month, day: day, hour: hour, minute: minute, second: second, microsecond: microsecond, time_zone: time_zone} = datetime
       new_month = month + mult
       {new_year, final_month} = if new_month > 12 do
         years_to_add = div(new_month - 1, 12)
         {year + years_to_add, rem(new_month - 1, 12) + 1}
       else
         {year, new_month}
       end
       days_in_new_month = Date.days_in_month(Date.new!(new_year, final_month, 1))
       final_day = min(day, days_in_new_month)
       new_date = Date.new!(new_year, final_month, final_day)
       {:ok, time} = Time.new(hour, minute, second, microsecond)
       {:ok, naive} = NaiveDateTime.new(new_date, time)
       DateTime.from_naive!(naive, time_zone)
     end

     # ✅ Good - logical blocks separated
     defp add_timeframe(datetime, {"M", mult}) do
       # Extract fields from datetime
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

       # Calculate new month and year
       new_month = month + mult

       {new_year, final_month} =
         if new_month > 12 do
           years_to_add = div(new_month - 1, 12)
           {year + years_to_add, rem(new_month - 1, 12) + 1}
         else
           {year, new_month}
         end

       # Adjust day for month overflow
       days_in_new_month = Date.days_in_month(Date.new!(new_year, final_month, 1))
       final_day = min(day, days_in_new_month)

       # Build new datetime
       new_date = Date.new!(new_year, final_month, final_day)
       {:ok, time} = Time.new(hour, minute, second, microsecond)
       {:ok, naive} = NaiveDateTime.new(new_date, time)

       DateTime.from_naive!(naive, time_zone)
     end
     ```

7. **Only add comments for complex or non-obvious logic**
   - Do not add comments to describe what the code does if it's already clear from the code itself
   - Blank lines are sufficient to separate logical blocks
   - Add comments only when the logic is particularly complex or non-intuitive
   - Example:
     ```elixir
     # ❌ Bad - unnecessary comments
     defp add_timeframe(datetime, {"D", mult}) do
       # Extract fields from datetime
       %DateTime{...} = datetime

       # Add days to date
       date = Date.new!(year, month, day)
       new_date = Date.add(date, mult)

       # Build new datetime
       {:ok, time} = Time.new(hour, minute, second, microsecond)
       ...
     end

     # ✅ Good - no comments needed, code is self-explanatory
     defp add_timeframe(datetime, {"D", mult}) do
       %DateTime{...} = datetime

       date = Date.new!(year, month, day)
       new_date = Date.add(date, mult)

       {:ok, time} = Time.new(hour, minute, second, microsecond)
       ...
     end

     # ✅ Good - comment explains non-obvious logic
     defp add_timeframe(datetime, {"M", mult}) do
       %DateTime{...} = datetime

       # Calculate new month handling year overflow
       # If new_month > 12, we need to increment year and wrap month
       new_month = month + mult
       {new_year, final_month} =
         if new_month > 12 do
           years_to_add = div(new_month - 1, 12)
           {year + years_to_add, rem(new_month - 1, 12) + 1}
         else
           {year, new_month}
         end
       ...
     end
     ```

8. **Document all public modules and functions**
   - Every public module MUST have a `@moduledoc` with a clear description
   - Every public function MUST have explicit documentation including:
     - `@doc` description of what the function does
     - `@spec` type specification with arguments and return types
     - Examples of usage (using `## Examples` section with doctest format)
   - Private modules should have `@moduledoc false` followed by comments explaining the module's purpose
   - Example:
     ```elixir
     # ❌ Bad - public module without documentation
     defmodule TheoryCraft.TimeFrame do
       def parse(timeframe) do
         # ...
       end
     end

     # ✅ Good - public module with full documentation
     defmodule TheoryCraft.TimeFrame do
       @moduledoc """
       Helpers for working with time frames.

       Provides functions to parse and validate timeframe strings like "m5" (5 minutes),
       "h1" (1 hour), or "D" (daily).
       """

       @type unit :: String.t()
       @type multiplier :: non_neg_integer()
       @type t :: {unit(), multiplier()}

       @doc """
       Parses a timeframe string into a tuple.

       ## Parameters
         - `timeframe` - A string representing a timeframe (e.g., "m5", "h1", "D")

       ## Returns
         - `{:ok, {unit, multiplier}}` on success
         - `:error` if the timeframe is invalid

       ## Examples
           iex> TheoryCraft.TimeFrame.parse("m5")
           {:ok, {"m", 5}}

           iex> TheoryCraft.TimeFrame.parse("h1")
           {:ok, {"h", 1}}

           iex> TheoryCraft.TimeFrame.parse("invalid")
           :error
       """
       @spec parse(String.t()) :: {:ok, t()} | :error
       def parse(timeframe) do
         # ...
       end
     end

     # ✅ Good - private module with @moduledoc false and comments
     defmodule TheoryCraft.Internal.Helper do
       @moduledoc false

       # This module provides internal helper functions for date manipulation.
       # It should not be used outside of TheoryCraft.TimeFrame.
       #
       # Functions in this module assume valid input and may raise on invalid data.

       def internal_helper(value) do
         # ...
       end
     end
     ```

### Code Formatting

**Always run `mix format` on modified Elixir files when finished**
- After completing all modifications, always format the changed `.ex` and `.exs` files
- `mix format` only works on Elixir source files (`.ex` and `.exs`)
- Do NOT run `mix format` on other files like `.md`, `.txt`, etc.
- This ensures consistent code style across the project
- Example workflow:
  ```bash
  # After modifying Elixir files
  mix format lib/theory_craft/processors/tick_to_candle_processor.ex
  mix format test/theory_craft/processors/tick_to_candle_processor_test.exs

  # Or format all Elixir files in the project
  mix format
  ```

## Dependencies

- `nimble_csv`: CSV parsing for data feeds
- `nimble_parsec`: Parser combinators (future use)
