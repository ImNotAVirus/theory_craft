# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TheoryCraft is an Elixir library for backtesting trading strategies using market data. It provides a GenStage-based streaming architecture for processing ticks and bars through configurable processors and data feeds.

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

The library uses a **GenStage pipeline architecture** where market data flows through stages:

1. **Data Source** → 2. **DataFeedStage** (Producer) → 3. **ProcessorStage** (Producer-Consumer) → 4. **Strategy/Output** (Consumer)

For parallel processing, the pipeline uses broadcast and aggregation:

1. **DataFeedStage** → 2. **BroadcastStage** → 3. **N × ProcessorStage** → 4. **AggregatorStage** → 5. **Output**

### Key Concepts

#### GenStage Pipeline Architecture

The system uses GenStage for backpressure-aware streaming:

- **DataFeed Behaviour**: Contract for data sources (`stream/1`, `stream!/1`)
- **Processor Behaviour**: Stateful transformations (`init/1`, `next/2`)
- **MarketEvent**: Wrapper with `data` map for multi-stream tracking
- **Stages**: GenStage wrappers around behaviours
  - `DataFeedStage`: Producer wrapping DataFeed
  - `ProcessorStage`: Producer-consumer wrapping Processor
  - `BroadcastStage`: Fan-out to parallel consumers
  - `AggregatorStage`: Synchronize and merge parallel outputs
  - `StageHelpers`: Shared utilities (option extraction, producer/consumer tracking, Flow termination pattern)

#### MarketSource

Fluent API for building GenStage pipelines dynamically:
- Supports multiple data feeds
- Builds layers: single processors or parallel (Broadcast → N×Processor → Aggregator)
- Automatic name generation for processors based on data source and timeframe

#### GenStage Options

All stages support:
- **GenStage/GenServer options**: `:name`, `:timeout`, `:debug`, `:spawn_opt`, `:hibernate_after`
- **Subscription options** for backpressure control:
  - `:min_demand`, `:max_demand` - Demand range
  - `:buffer_size` - Buffer size (default: 10000)
  - `:buffer_keep` - `:first` or `:last` when buffer is full (default: `:last`)

**Important**: `AggregatorStage` uses `:max_demand` internally for manual demand management, so this option cannot be passed as a subscription option for that stage.

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

       alias TheoryCraft.MarketSource
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

1. **Test module-specific behavior, not standard library**
   - DO NOT test Enum protocol implementations (map, filter, reduce, member, take, etc.)
   - DO NOT test Access protocol extensively - just verify it works with 1-2 basic tests
   - Focus on the module's unique business logic and edge cases
   - Example:
     ```elixir
     # ❌ Bad - testing stdlib behavior
     test "map works" do
       series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2)
       result = Enum.map(series, &(&1 * 2))
       assert result == [4, 2]
     end

     test "filter works" do
       series = DataSeries.new() |> DataSeries.add(1) |> DataSeries.add(2)
       result = Enum.filter(series, &(&1 > 1))
       assert result == [2]
     end

     # ✅ Good - testing module-specific logic
     test "circular buffer overwrites oldest value when full" do
       series = DataSeries.new(max_size: 2)
       series = series |> DataSeries.add(1) |> DataSeries.add(2) |> DataSeries.add(3)
       assert DataSeries.get(series, 0) == 3
       assert DataSeries.get(series, 1) == 2
       assert DataSeries.get(series, 2) == nil  # oldest value was dropped
     end
     ```

2. **Follow consistent test module structure**
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

3. **Extract large data structures and repeated setup into helper functions**
   - Large lists or complex structs → extract to private functions
   - Repeated setup code → extract to private functions
   - **CRITICAL**: NEVER refactor calls to the module being tested
   - Only extract calls to dependency modules (setup, mocks, etc.)
   - Example:
     ```elixir
     # In ProcessorStageTest - testing ProcessorStage module

     # ❌ Bad - extracting calls to module being tested
     test "processes events" do
       processor = start_processor_stage(opts)  # ❌ Hides what's being tested
     end

     # ✅ Good - keep tested module calls visible
     test "processes events" do
       producer = start_producer(feed)  # ✅ Helper for dependency

       {:ok, processor} = ProcessorStage.start_link(...)  # ✅ Tested module call visible
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
  mix format lib/theory_craft/processors/tick_to_bar_processor.ex
  mix format test/theory_craft/processors/tick_to_bar_processor_test.exs

  # Or format all Elixir files in the project
  mix format
  ```
