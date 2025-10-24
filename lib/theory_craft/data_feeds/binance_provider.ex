defmodule TheoryCraft.DataFeeds.BinanceProvider do
  @moduledoc """
  `ExchangeDataFeed` provider backed by the public Binance HTTP API.

  Only a subset of the API surface is wrapped at the moment - enough to stream
  historical klines and poll the most recent klines for live updates. The
  provider is intentionally transport-agnostic so tests (or calling code) can
  inject a fake HTTP client.
  """

  @behaviour TheoryCraft.DataFeeds.ExchangeDataFeed.Provider

  alias TheoryCraft.ExchangeData

  @default_historical_limit 500
  @default_live_limit 2

  @spot_base_url "https://api.binance.com"
  @usdm_base_url "https://fapi.binance.com"
  @coinm_base_url "https://dapi.binance.com"

  @spot_kline_path "/api/v3/klines"
  @futures_kline_path "/fapi/v1/klines"
  @coinm_kline_path "/dapi/v1/klines"

  @type market ::
          :spot
          | :usdm_futures
          | :coinm_futures

  @type http_client :: (map() -> {:ok, term()} | {:error, term()})

  ## ExchangeDataFeed.Provider callbacks

  @impl true
  def fetch_historical(opts) do
    limit = normalize_limit(Keyword.get(opts, :limit), @default_historical_limit)

    with {:ok, config} <- build_config(opts),
         {:ok, klines} <- fetch_klines(config, limit, opts) do
      {:ok, Enum.map(klines, &kline_to_exchange_data(&1, config.symbol))}
    end
  end

  @impl true
  def start_live(opts) do
    with {:ok, config} <- build_config(opts) do
      extra_params =
        opts
        |> Keyword.get(:live_params, [])
        |> normalize_keyword_option!(:live_params)

      state = %{
        config: config,
        poll_limit: normalize_limit(Keyword.get(opts, :live_limit), @default_live_limit),
        last_close_time: Keyword.get(opts, :last_close_time),
        extra_params: extra_params
      }

      {:ok, state}
    end
  end

  @impl true
  def fetch_live(%{config: config} = state) do
    poll_limit = state.poll_limit || @default_live_limit
    params = state.extra_params || []

    case fetch_klines(config, poll_limit, params) do
      {:ok, klines} ->
        events =
          klines
          |> Enum.map(&kline_to_exchange_data(&1, config.symbol))
          |> Enum.filter(&newer_than?(&1.time, state.last_close_time))

        new_last_close_time =
          case List.last(events) do
            %ExchangeData{time: time} -> time
            _ -> state.last_close_time
          end

        {:ok, {events, %{state | last_close_time: new_last_close_time}}}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def stop_live(_state), do: :ok

  ## Internal helpers

  defp build_config(opts) do
    with {:ok, symbol} <- fetch_required(opts, :symbol),
         {:ok, interval} <- fetch_required(opts, :interval) do
      market = Keyword.get(opts, :market, :spot)
      http_client = Keyword.get(opts, :http_client, &default_http_client/1)

      req_options =
        opts
        |> Keyword.get(:req_options, [])
        |> normalize_keyword_option!(:req_options)

      base_url = Keyword.get(opts, :base_url, base_url_for(market))
      path = Keyword.get(opts, :path, kline_path_for(market))

      {:ok,
       %{
         symbol: normalize_symbol(symbol),
         interval: normalize_interval(interval),
         market: market,
         base_url: base_url,
         path: path,
         http_client: http_client,
         req_options: req_options
       }}
    end
  end

  defp fetch_klines(config, limit, opts) do
    request = %{
      url: config.base_url <> config.path,
      params:
        [
          symbol: config.symbol,
          interval: config.interval,
          limit: limit
        ]
        |> maybe_put_param("startTime", Keyword.get(opts, :start_time))
        |> maybe_put_param("endTime", Keyword.get(opts, :end_time)),
      req_opts: config.req_options
    }

    case config.http_client.(request) do
      {:ok, body} when is_list(body) ->
        {:ok, body}

      {:ok, %{"code" => code, "msg" => msg}} ->
        {:error, {:binance_error, code, msg}}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp default_http_client(%{url: url, params: params} = request) do
    opts = Keyword.merge([url: url, params: params, json: true], Map.get(request, :req_opts, []))

    case Req.request(opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        {:error, {:request_error, exception}}
    end
  end

  defp kline_to_exchange_data(
         [
           _open_time,
           _open_price,
           _high,
           _low,
           close_price,
           volume,
           close_time | _
         ],
         symbol
       ) do
    %ExchangeData{
      time: close_time |> parse_milliseconds() |> DateTime.from_unix!(:millisecond),
      symbol: symbol,
      price: parse_float(close_price),
      volume: parse_float(volume),
      open_interest: nil,
      funding_rate: nil
    }
  end

  defp kline_to_exchange_data(_kline, symbol) do
    %ExchangeData{symbol: symbol}
  end

  defp newer_than?(_time, nil), do: true

  defp newer_than?(time, last_time) do
    DateTime.compare(time, last_time) == :gt
  end

  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_option, key}}
    end
  end

  defp base_url_for(:spot), do: @spot_base_url
  defp base_url_for(:usdm_futures), do: @usdm_base_url
  defp base_url_for(:coinm_futures), do: @coinm_base_url

  defp base_url_for(other),
    do: raise(ArgumentError, "Unsupported Binance market #{inspect(other)}")

  defp kline_path_for(:spot), do: @spot_kline_path
  defp kline_path_for(:usdm_futures), do: @futures_kline_path
  defp kline_path_for(:coinm_futures), do: @coinm_kline_path

  defp kline_path_for(other),
    do: raise(ArgumentError, "Unsupported Binance market #{inspect(other)}")

  defp maybe_put_param(params, _key, nil), do: params

  defp maybe_put_param(params, key, %DateTime{} = datetime) do
    Keyword.put(params, key, DateTime.to_unix(datetime, :millisecond))
  end

  defp maybe_put_param(params, key, %NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:millisecond)
    |> then(&Keyword.put(params, key, &1))
  end

  defp maybe_put_param(params, key, value) when is_integer(value) do
    Keyword.put(params, key, value)
  end

  defp maybe_put_param(params, key, value) when is_binary(value) do
    Keyword.put(params, key, value)
  end

  defp maybe_put_param(params, _key, _value), do: params

  defp normalize_symbol(symbol) when is_binary(symbol), do: String.upcase(symbol)

  defp normalize_symbol(symbol) when is_atom(symbol),
    do: symbol |> Atom.to_string() |> String.upcase()

  defp normalize_interval(interval) when is_binary(interval), do: interval
  defp normalize_interval(interval) when is_atom(interval), do: Atom.to_string(interval)

  defp normalize_limit(nil, default), do: default

  defp normalize_limit(value, _default) when is_integer(value) and value > 0 do
    value
  end

  defp normalize_limit(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> default
    end
  end

  defp normalize_limit(_value, default), do: default

  defp normalize_keyword_option!(value, _key) when value in [nil, []], do: []

  defp normalize_keyword_option!(value, key) when is_list(value) do
    if Keyword.keyword?(value) do
      value
    else
      raise ArgumentError, "#{inspect(key)} must be a keyword list, got: #{inspect(value)}"
    end
  end

  defp normalize_keyword_option!(value, key) do
    raise ArgumentError, "#{inspect(key)} must be a keyword list, got: #{inspect(value)}"
  end

  defp parse_milliseconds(value) when is_integer(value), do: value

  defp parse_milliseconds(value) when is_binary(value) do
    value
    |> String.to_integer()
  end

  defp parse_float(nil), do: nil
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end
end
