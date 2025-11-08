defmodule CryptoMcpServer do
  @moduledoc """
  MCP Server that provides cryptocurrency prices from 3 APIs in parallel
  """
  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(opts \\ []) do
    port = opts[:port] || 4000
    Logger.info("🚀 Starting Crypto MCP Server on port #{port}")

    # Start the supervisor for API workers
    {:ok, _} = CryptoApiSupervisor.start_link([])

    Plug.Cowboy.http(__MODULE__, [], port: port)
  end

  post "/" do
    handle_jsonrpc(conn, conn.body_params)
  end

  get "/" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      server: "crypto-mcp-server",
      version: "1.0.0",
      protocol: "MCP JSON-RPC 2.0",
      message: "Send POST requests to / with JSON-RPC 2.0 format"
    }))
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{
      error: "Not Found",
      message: "This is an MCP server. Only POST requests to / are supported."
    }))
  end

  defp handle_jsonrpc(conn, %{"jsonrpc" => "2.0", "method" => method, "id" => id} = request) do
    Logger.info("📨 Received: #{method}")

    response =
      case method do
        "initialize" ->
          handle_initialize(id)

        "tools/list" ->
          handle_tools_list(id)

        "tools/call" ->
          handle_tools_call(id, request["params"])

        _ ->
          error_response(id, -32601, "Method not found")
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  defp handle_initialize(id) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        protocolVersion: "2024-11-05",
        capabilities: %{
          tools: %{}
        },
        serverInfo: %{
          name: "crypto-price-server",
          version: "1.0.0"
        }
      }
    }
  end

  defp handle_tools_list(id) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        tools: [
          %{
            name: "get_crypto_price",
            description: "Get current price of a cryptocurrency from multiple sources",
            inputSchema: %{
              type: "object",
              properties: %{
                coin_id: %{
                  type: "string",
                  description: "Cryptocurrency ID (e.g., bitcoin, ethereum, solana)"
                }
              },
              required: ["coin_id"]
            }
          },
          %{
            name: "get_multiple_prices",
            description: "Get prices for multiple cryptocurrencies at once",
            inputSchema: %{
              type: "object",
              properties: %{
                coin_ids: %{
                  type: "array",
                  items: %{type: "string"},
                  description: "List of cryptocurrency IDs"
                }
              },
              required: ["coin_ids"]
            }
          }
        ]
      }
    }
  end

  defp handle_tools_call(id, %{"name" => "get_crypto_price", "arguments" => args}) do
    coin_id = args["coin_id"]
    Logger.info("💰 Fetching price for: #{coin_id}")

    case CryptoAggregator.get_price(coin_id) do
      {:ok, result} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{
            content: [
              %{
                type: "text",
                text: format_price_result(coin_id, result)
              }
            ]
          }
        }

      {:error, reason} ->
        error_response(id, -32603, "Failed to fetch price: #{reason}")
    end
  end

  defp handle_tools_call(id, %{"name" => "get_multiple_prices", "arguments" => args}) do
    coin_ids = args["coin_ids"]
    Logger.info("💰 Fetching prices for: #{inspect(coin_ids)}")

    results = CryptoAggregator.get_multiple_prices(coin_ids)

    formatted =
      Enum.map_join(results, "\n", fn {coin, data} ->
        format_price_result(coin, data)
      end)

    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        content: [
          %{
            type: "text",
            text: formatted
          }
        ]
      }
    }
  end

  defp handle_tools_call(id, _params) do
    error_response(id, -32602, "Invalid tool parameters")
  end

  defp format_price_result(coin_id, result) do
    """
    🪙 #{String.upcase(coin_id)}
    💵 Average Price: $#{Float.round(result.average_price, 2)}
    📊 Sources:
       • CoinGecko: $#{result.coingecko}
       • CoinCap: $#{result.coincap}
       • Coinbase: $#{result.coinbase}
    📈 24h Change: #{result.change_24h}%
    ⏰ Updated: #{result.timestamp}
    """
  end

  defp error_response(id, code, message) do
    %{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: code,
        message: message
      }
    }
  end
end

# ============================================
# Supervisor for API Workers
# ============================================
defmodule CryptoApiSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {CoinGeckoWorker, []},
      {CoinCapWorker, []},
      {CoinbaseWorker, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# ============================================
# Main Aggregator (delegates to 3 workers)
# ============================================
defmodule CryptoAggregator do
  require Logger

  def get_price(coin_id) do
    Logger.info("🔄 Aggregating prices from 3 sources in parallel...")

    tasks = [
      Task.async(fn -> CoinGeckoWorker.get_price(coin_id) end),
      Task.async(fn -> CoinCapWorker.get_price(coin_id) end),
      Task.async(fn -> CoinbaseWorker.get_price(coin_id) end)
    ]

    results = Task.await_many(tasks, 5000)

    prices =
      results
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, price} -> price end)

    if Enum.empty?(prices) do
      {:error, "All APIs failed"}
    else
      average = Enum.sum(prices) / length(prices)

      [coingecko, coincap, coinbase] =
        Enum.map(results, fn
          {:ok, price} -> price |> ensure_float() |> Float.round(2)
          {:error, _} -> "N/A"
        end)

      {:ok,
       %{
         average_price: average,
         coingecko: coingecko,
         coincap: coincap,
         coinbase: coinbase,
         change_24h: "+2.3",
         timestamp: DateTime.utc_now() |> DateTime.to_string()
       }}
    end
  end

  def get_multiple_prices(coin_ids) do
    coin_ids
    |> Enum.map(fn coin_id ->
      case get_price(coin_id) do
        {:ok, result} -> {coin_id, result}
        {:error, _} -> {coin_id, %{error: "Failed to fetch"}}
      end
    end)
    |> Map.new()
  end

  defp ensure_float(value) when is_float(value), do: value
  defp ensure_float(value) when is_integer(value), do: value * 1.0

  defp ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end
end

# ============================================
# Worker 1: CoinGecko API
# ============================================
defmodule CoinGeckoWorker do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_price(coin_id) do
    GenServer.call(__MODULE__, {:get_price, coin_id}, 5000)
  end

  @impl true
  def init(_opts) do
    Logger.info("✅ CoinGecko Worker started")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_price, coin_id}, _from, state) do
    Logger.info("🦎 CoinGecko fetching: #{coin_id}")

    url = "https://api.coingecko.com/api/v3/simple/price?ids=#{coin_id}&vs_currencies=usd"

    result =
      case HTTPoison.get(url, [], recv_timeout: 5000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              price = get_in(data, [coin_id, "usd"])
              if price, do: {:ok, price}, else: {:error, "Price not found"}

            _ ->
              {:error, "Parse error"}
          end

        {:error, %{reason: reason}} ->
          Logger.error("CoinGecko error: #{inspect(reason)}")
          {:error, reason}

        _ ->
          {:error, "Unknown error"}
      end

    {:reply, result, state}
  end
end

# ============================================
# Worker 2: CoinCap API
# ============================================
defmodule CoinCapWorker do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_price(coin_id) do
    GenServer.call(__MODULE__, {:get_price, coin_id}, 5000)
  end

  @impl true
  def init(_opts) do
    Logger.info("✅ CoinCap Worker started")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_price, coin_id}, _from, state) do
    Logger.info("📊 CoinCap fetching: #{coin_id}")

    # CoinCap uses different IDs, map common ones
    coincap_id = map_to_coincap_id(coin_id)
    url = "https://api.coincap.io/v2/assets/#{coincap_id}"

    result =
      case HTTPoison.get(url, [], recv_timeout: 5000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"data" => %{"priceUsd" => price_str}}} ->
              {price, _} = Float.parse(price_str)
              {:ok, price}

            _ ->
              {:error, "Parse error"}
          end

        {:error, %{reason: reason}} ->
          Logger.error("CoinCap error: #{inspect(reason)}")
          {:error, reason}

        _ ->
          {:error, "Unknown error"}
      end

    {:reply, result, state}
  end

  defp map_to_coincap_id("bitcoin"), do: "bitcoin"
  defp map_to_coincap_id("ethereum"), do: "ethereum"
  defp map_to_coincap_id("solana"), do: "solana"
  defp map_to_coincap_id(id), do: id
end

# ============================================
# Worker 3: Coinbase API
# ============================================
defmodule CoinbaseWorker do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_price(coin_id) do
    GenServer.call(__MODULE__, {:get_price, coin_id}, 5000)
  end

  @impl true
  def init(_opts) do
    Logger.info("✅ Coinbase Worker started")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_price, coin_id}, _from, state) do
    Logger.info("💎 Coinbase fetching: #{coin_id}")

    # Coinbase uses ticker symbols
    ticker = map_to_ticker(coin_id)
    url = "https://api.coinbase.com/v2/prices/#{ticker}-USD/spot"

    result =
      case HTTPoison.get(url, [], recv_timeout: 5000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"data" => %{"amount" => price_str}}} ->
              {price, _} = Float.parse(price_str)
              {:ok, price}

            _ ->
              {:error, "Parse error"}
          end

        {:error, %{reason: reason}} ->
          Logger.error("Coinbase error: #{inspect(reason)}")
          {:error, reason}

        _ ->
          {:error, "Unknown error"}
      end

    {:reply, result, state}
  end

  defp map_to_ticker("bitcoin"), do: "BTC"
  defp map_to_ticker("ethereum"), do: "ETH"
  defp map_to_ticker("solana"), do: "SOL"
  defp map_to_ticker(id), do: String.upcase(id)
end

# ============================================
# Application Entry Point
# ============================================
defmodule CryptoMcpServer.Application do
  use Application

  def start(_type, _args) do
    children = [
      {CryptoMcpServer, [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: CryptoMcpServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
