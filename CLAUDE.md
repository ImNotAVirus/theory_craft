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

## Dependencies

- `nimble_csv`: CSV parsing for data feeds
- `nimble_parsec`: Parser combinators (future use)

## Coding Guidelines

### Elixir Best Practices

#### Module Structure and Organization

1. **Follow consistent module structure**
   - Every module must follow this format with proper ordering and spacing
   - Order: `use` → `require` → `import` → `alias`
   - Separate sections with comments and blank lines
   - Example:
     ```elixir
     defmodule KinoTheoryCraft.TheoryCraftCell do
       @moduledoc """
       Smart cell implementation for TheoryCraft integration.

       Provides an interactive UI for configuring and executing
       TheoryCraft data processing tasks in Livebook.
       """

       use Kino.JS, assets_path: "lib/assets/theory_craft_cell", entrypoint: "build/main.js"
       use Kino.JS.Live
       use Kino.SmartCell, name: "TheoryCraft"

       require Logger

       import TheoryCraft.TimeFrame

       alias TheoryCraft.MarketSimulator
       alias TheoryCraft.Processor

       ## Module attributes

       @task_groups [...]

       ## Public API

       @doc """
       Initializes the smart cell state from saved attributes.
       """
       @spec init(map(), Kino.JS.Live.Context.t()) :: {:ok, Kino.JS.Live.Context.t()}
       def init(attrs, ctx) do
         # ...
       end

       ## Internal use ONLY

       @doc false
       @spec field_defaults_for(String.t()) :: map()
       def field_defaults_for(task_id) do
         # ...
       end

       ## Private functions

       defp task_groups(), do: @task_groups

       defp tasks(), do: Enum.flat_map(task_groups(), & &1.tasks)
     end
     ```

2. **Never use multiline tuples**
   - Tuples should always be on a single line
   - For complex return values, assign to a variable first, then return
   - This improves readability and makes the return value explicit
   - Example:
     ```elixir
     # ❌ Bad - multiline tuple
     def handle_connect(ctx) do
       {:ok,
        %{
          fields: ctx.assigns.fields,
          task_groups: task_groups(),
          input_variables: ctx.assigns.input_variables
        }, ctx}
     end

     # ✅ Good - assign to variable first
     def handle_connect(ctx) do
       payload = %{
         fields: ctx.assigns.fields,
         task_groups: task_groups(),
         input_variables: ctx.assigns.input_variables
       }

       {:ok, payload, ctx}
     end
     ```

     ```elixir
     # ❌ Bad - multiline tuple in init
     def init(attrs, ctx) do
       {:ok,
        assign(ctx,
          fields: fields,
          input_variables: [],
          task_groups: task_groups()
        )}
     end

     # ✅ Good - assign to variable first
     def init(attrs, ctx) do
       new_ctx = assign(ctx,
         fields: fields,
         input_variables: [],
         task_groups: task_groups()
       )

       {:ok, new_ctx}
     end
     ```

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

9. **End documentation examples with a blank line**
   - When `@doc` or `@moduledoc` blocks end with examples (code snippets or `iex>` blocks), always add a blank line before the closing `"""`
   - This improves visual separation and readability
   - Example:
     ```elixir
     # ❌ Bad - no blank line before closing
     @doc """
     Processes a market event.

     ## Examples

         iex> process(event)
         {:ok, result}
     """

     # ✅ Good - blank line before closing
     @doc """
     Processes a market event.

     ## Examples

         iex> process(event)
         {:ok, result}

     """
     ```

     ```elixir
     # Note: if examples are NOT at the end, no blank line is needed
     @doc """
     Processes a market event.

     ## Examples

         iex> process(event)
         {:ok, result}

     ## Additional Notes

     This function handles errors gracefully.
     """
     ```

### Test Organization and Readability

1. **Follow consistent test module structure**
   - Test modules must follow a consistent structure with section comments
   - Use `## Setup` for the setup/setup_all section
   - Use `## Tests` for the test section
   - Example:
     ```elixir
     defmodule TheoryCraft.SomeModuleTest do
       use ExUnit.Case, async: true

       alias TheoryCraft.SomeModule

       ## Setup

       setup do
         # Setup code
         {:ok, some_data: data}
       end

       ## Tests

       describe "some functionality" do
         test "does something", %{some_data: data} do
           # Test code
         end
       end

       ## Private helper functions

       defp build_test_data do
         # Helper code
       end
     end
     ```

2. **Extract large data structures into private helper functions**
   - Tests must be clear and readable
   - Large lists, complex structs, or repeated test data should be extracted into private helper functions
   - This keeps the test body focused on the actual test logic
   - Example:
     ```elixir
     # ❌ Bad - large list clutters the setup
     setup do
       ticks = [
         %Tick{
           time: ~U[2024-01-01 00:00:00.000000Z],
           ask: 2500.0,
           bid: 2499.0,
           ask_volume: 100.0,
           bid_volume: 150.0
         },
         %Tick{
           time: ~U[2024-01-01 00:01:00.000000Z],
           ask: 2501.0,
           bid: 2500.0,
           ask_volume: 100.0,
           bid_volume: 150.0
         },
         # ... 20 more ticks ...
       ]

       {:ok, ticks: ticks}
     end

     # ✅ Good - extracted to private helper function
     setup do
       ticks = build_test_ticks()
       {:ok, ticks: ticks}
     end

     # Private helper functions

     defp build_test_ticks do
       [
         %Tick{
           time: ~U[2024-01-01 00:00:00.000000Z],
           ask: 2500.0,
           bid: 2499.0,
           ask_volume: 100.0,
           bid_volume: 150.0
         },
         %Tick{
           time: ~U[2024-01-01 00:01:00.000000Z],
           ask: 2501.0,
           bid: 2500.0,
           ask_volume: 100.0,
           bid_volume: 150.0
         },
         # ... 20 more ticks ...
       ]
     end
     ```

   - This also allows reusing the same data in multiple test files
   - For very common test data, consider creating a test support module (e.g., `test/support/fixtures.ex`)

3. **Refactor repeated code into private helper functions**
   - Tests must be clear and concise
   - When the same code pattern is repeated multiple times in tests, extract it into a private helper function
   - **IMPORTANT**: NEVER refactor calls to the module being tested - always keep these in the test functions themselves
   - Only refactor calls to other modules (dependencies, setup code, etc.)
   - This makes tests easier to read and maintain while keeping the tested functionality visible
   - Example:
     ```elixir
     # In ProcessorStageTest - testing ProcessorStage module

     # ❌ Bad - refactoring calls to the module being tested
     test "test 1" do
       processor = start_processor_stage(opts)  # ❌ Don't extract ProcessorStage calls
       # ...
     end

     # ✅ Good - keep calls to module being tested in the test
     test "test 1" do
       producer = start_producer(tick_feed)  # ✅ Helper for DataFeedStage (dependency)

       {:ok, processor} =
         ProcessorStage.start_link(  # ✅ Direct call to module being tested
           {TickToCandleProcessor, [data: "xauusd", timeframe: "m5", name: "xauusd"]},
           subscribe_to: [producer]
         )
       # ...
     end

     ## Private functions

     # ✅ Good - helper for dependency module
     defp start_producer(feed, name \\ "xauusd") do
       {:ok, producer} = DataFeedStage.start_link({MemoryDataFeed, [from: feed]}, name: name)
       producer
     end
     ```

     ```elixir
     # In DataFeedStageTest - testing DataFeedStage module

     # ❌ Bad - refactoring calls to the module being tested
     defp start_data_feed_stage(feed) do
       {:ok, stage} = DataFeedStage.start_link({MemoryDataFeed, [from: feed]}, name: "xauusd")
       stage
     end

     # ✅ Good - keep DataFeedStage calls directly in tests
     test "test 1" do
       {:ok, stage} = DataFeedStage.start_link({MemoryDataFeed, [from: feed]}, name: "xauusd")
       # ...
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
