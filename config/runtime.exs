import Config

## General application configuration

config :logger, :console,
  level: :debug,
  format: "[$time] [$level] $metadata| $message\n",
  metadata: [:module],
  colors: [info: :green]

## Environment specific configuration

if config_env() == :test do
  config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

  config :logger, :console, level: :warning
end

if config_env() == :prod do
  config :logger, :console,
    level: :info,
    format: "[$date $time] [$node] [$level] $metadata| $message\n"
end
