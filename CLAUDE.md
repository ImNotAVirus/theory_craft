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
