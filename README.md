# Aya Agent - Custom MCP Implementation with Gemini AI

> A hackathon project demonstrating a full-stack implementation of the Model Context Protocol (MCP) from scratch, featuring a tool-augmented AI agent powered by Google's Gemini API with real-time cryptocurrency price aggregation.

![Demo](aya.gif)

## What Makes This Project Special

This isn't just another AI chatbot - it's a **production-ready demonstration** of modern AI agent architecture:

- **Custom MCP Server & Client** - Built from scratch in Elixir, implementing JSON-RPC 2.0 protocol
- **Tool-Augmented LLM** - Gemini AI with real-time tool calling capabilities
- **Parallel API Aggregation** - Fetches crypto prices from 3 sources simultaneously with fault tolerance
- **Real-Time Web UI** - Phoenix LiveView for instant updates without page reloads
- **Agentic Loop** - Recursive tool calling pattern for complex multi-step queries
- **Production Patterns** - OTP supervision, error handling, timeouts, and concurrent workers

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Phoenix Web UI (LiveView)                │
│                   Real-time chat interface                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                   MCP Client (GenServer)                    │
│  • Manages MCP server connections                           │
│  • Orchestrates Gemini API communication                    │
│  • Handles tool execution callbacks                         │
└────────┬──────────────────────────────────┬─────────────────┘
         │                                  │
         │ HTTP/JSON-RPC                    │ HTTPS
         ↓                                  ↓
┌──────────────────────┐        ┌──────────────────────────┐
│   MCP Server         │        │    Gemini 2.0 Flash      │
│   (Port 4000)        │        │  (Tool-Augmented LLM)    │
│                      │        └──────────────────────────┘
│  JSON-RPC 2.0 API    │
│  • tools/list        │
│  • tools/call        │
└─────────┬────────────┘
          │
          ↓
┌─────────────────────────────────────────────────────────────┐
│              Crypto Price Aggregator                        │
│         Parallel API fetching with Task.async               │
└─┬───────────────────┬──────────────────────┬────────────────┘
  │                   │                      │
  ↓                   ↓                      ↓
┌──────────┐    ┌──────────┐         ┌──────────┐
│CoinGecko │    │ CoinCap  │         │Coinbase  │
│ Worker   │    │  Worker  │         │ Worker   │
└──────────┘    └──────────┘         └──────────┘
```

## Custom MCP Server Implementation

### Location
`/mcp_server/lib/CryptoMcpServer.ex`

### Features

**JSON-RPC 2.0 Compliant Server**
- Implements `initialize`, `tools/list`, and `tools/call` methods
- Proper error codes (-32601, -32603) and response format
- Built using Plug.Router without external MCP libraries

**Parallel Crypto Price Aggregation**
```elixir
# Fetches from 3 APIs simultaneously with 5000ms timeout
tasks = [
  Task.async(fn -> CoinGeckoWorker.get_price(coin_id) end),
  Task.async(fn -> CoinCapWorker.get_price(coin_id) end),
  Task.async(fn -> CoinbaseWorker.get_price(coin_id) end)
]
results = Task.await_many(tasks, 5000)
```

**Available Tools**
1. `get_crypto_price` - Fetch price for a single cryptocurrency
2. `get_multiple_prices` - Batch fetch prices for multiple coins

**Production-Ready Architecture**
- Each API has its own GenServer worker for process isolation
- Supervised with `:one_for_one` restart strategy
- Fault-tolerant: if one API fails, others continue
- Smart mapping between different API formats

## Custom MCP Client Implementation

### Location
`/lib/mcp_client.ex`

### Features

**GenServer-Based Client**
- Manages connections to multiple MCP servers
- Retrieves and caches available tools
- Routes tool calls to appropriate servers

**Tool-Augmented LLM Pattern**
```elixir
User Input
    ↓
McpClient.chat(message)
    ↓
Gemini API (with tool definitions)
    ↓
[Gemini decides: Need tool?]
    ├─ YES → Execute tool via MCP → Feed result back → Final response
    └─ NO  → Direct text response
```

**Agentic Loop**
- Implements recursive tool calling
- Gemini can make multiple tool calls in sequence
- Full conversation context maintained
- Results feed back into the conversation for informed responses

## Gemini API as "Aya Agent"

Since the Aya API is not yet available, this project uses **Google's Gemini 2.0 Flash** as the reasoning engine:

**Model**: `gemini-2.0-flash-exp`

**Role**: Intelligent orchestrator that:
- Understands user intent
- Decides when to use tools
- Processes tool results
- Generates natural language responses

**Integration Highlights**
- Converts MCP tool schemas to Gemini function declarations
- Maintains conversation history for context
- Handles multi-turn tool-calling workflows
- API key validation at compile time

## Phoenix LiveView Real-Time UI

### Location
`/lib/aya_agent_web/live/chat_live.ex`

### Features

**WebSocket-Powered Chat Interface**
- Real-time message updates without page reloads
- Loading states during API calls
- Scroll-to-bottom on new messages
- Beautiful gradient UI with Tailwind CSS

**Seamless GenServer Integration**
```elixir
# Async processing pattern
def handle_event("send_message", %{"message" => message}, socket) do
  send(self(), {:send_to_llm, message})
  {:noreply, socket}
end

def handle_info({:send_to_llm, message}, socket) do
  response = McpClient.chat(message)
  # Update UI in real-time
end
```

## Quick Start

### Prerequisites

```bash
# Install Elixir (1.15+) and Phoenix
brew install elixir
mix archive.install hex phx_new

# Get a Gemini API key
# Visit: https://ai.google.dev/
export GEMINI_API_KEY="your-api-key-here"
```

### Installation

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd aya_agent

# 2. Install dependencies
mix setup

# 3. Start the MCP server (in one terminal)
cd mcp_server
mix deps.get
iex -S mix
# Server runs on http://localhost:4000

# 4. Start the Phoenix app (in another terminal)
cd ..
mix phx.server
# Visit http://localhost:4000
```

### Usage

**Web UI**
1. Open browser to `http://localhost:4000`
2. Type a message like "What's the price of Bitcoin?"
3. Watch as Gemini calls the MCP tools and returns aggregated data

**CLI Mode**
```bash
iex -S mix
iex> AyaAgent.CLI.run()
# Interactive terminal chat
```

## Example Interactions

**Query**: "What's the current price of Bitcoin and Ethereum?"

**Response**:
```
Based on aggregated data from CoinGecko, CoinCap, and Coinbase:

• Bitcoin (BTC): $45,230.42 (↑ 2.3% 24h)
• Ethereum (ETH): $2,891.15 (↑ 1.8% 24h)

Data sources:
- CoinGecko: $45,245.00
- CoinCap: $45,220.50
- Coinbase: $45,225.75
```

## Project Structure

```
aya_agent/
├── lib/
│   ├── mcp_client.ex              # MCP client GenServer
│   ├── aya_agent/
│   │   └── application.ex         # OTP Application supervisor
│   └── aya_agent_web/
│       ├── live/chat_live.ex      # Real-time chat UI
│       ├── router.ex              # Phoenix routes
│       └── endpoint.ex            # Phoenix endpoint
├── mcp_server/                    # Standalone MCP server project
│   └── lib/
│       ├── CryptoMcpServer.ex     # Main MCP server
│       ├── CryptoAggregator.ex    # Price aggregation logic
│       ├── CoinGeckoWorker.ex     # CoinGecko API GenServer
│       ├── CoinCapWorker.ex       # CoinCap API GenServer
│       └── CoinbaseWorker.ex      # Coinbase API GenServer
├── config/
│   ├── config.exs                 # Base configuration
│   ├── dev.exs                    # Development config
│   └── runtime.exs                # Production config
└── assets/                        # Frontend assets
```

## Technical Stack

**Backend**
- Elixir 1.15+ - Concurrent, fault-tolerant language
- Phoenix 1.8.1 - Web framework
- Phoenix LiveView 1.1 - Real-time UI
- Plug & Cowboy - HTTP servers
- GenServer & Task - OTP concurrency primitives

**Frontend**
- Phoenix LiveView (no React/Vue needed!)
- Tailwind CSS 4.1.12 - Styling
- Heroicons - Icons
- Esbuild - JavaScript bundler

**External APIs**
- Google Gemini 2.0 Flash - LLM
- CoinGecko API - Crypto prices
- CoinCap API - Crypto prices
- Coinbase API - Crypto prices

## Impressive Technical Highlights

### 1. GenServer-per-API Pattern
Each external API gets its own GenServer for:
- Process isolation
- Independent supervision
- Scalability (can add caching, rate limiting per API)

### 2. Fault-Tolerant API Aggregation
```elixir
# If one API fails, returns "N/A" but continues with others
def aggregate_prices(coin_id) do
  results = fetch_all_sources(coin_id)

  valid_prices = results
    |> Enum.filter(&(&1 != "N/A"))
    |> Enum.map(&parse_price/1)

  average_price(valid_prices)
end
```

### 3. Agentic Loop Implementation
Recursive tool calling with conversation context:
```elixir
defp call_gemini_with_tools(conversation_history, available_tools) do
  case gemini_response do
    %{"function_call" => fc} ->
      result = execute_tool(fc)
      # Feed result back to Gemini
      call_gemini_with_tools(
        conversation_history ++ [tool_result],
        available_tools
      )
    %{"text" => text} ->
      {:ok, text}
  end
end
```

### 4. Dual Frontend Support
Same backend powers both:
- Web UI (Phoenix LiveView)
- CLI (Interactive terminal)

### 5. No External MCP Libraries
Built the entire MCP protocol implementation from scratch - demonstrates deep understanding of:
- JSON-RPC 2.0 specification
- HTTP/SSE transport
- Tool schema definitions
- Error handling patterns

## Environment Variables

```bash
# Required
GEMINI_API_KEY=<your-gemini-api-key>

# Optional (with defaults)
PORT=4000                              # Phoenix server port
PHX_HOST=localhost                     # Production host
SECRET_KEY_BASE=<long-random-string>   # Production secret
```

## Development

```bash
# Run tests
mix test

# Format code
mix format

# Run precommit checks
mix precommit  # Compile, format, test, check unused deps

# Start interactive shell
iex -S mix

# Build assets
mix assets.build
```

## Deployment

The project is production-ready with:
- Proper supervision trees
- Error handling and timeouts
- Configurable via environment variables
- Docker-ready (Elixir releases)

See `config/runtime.exs` for production configuration.

## Future Enhancements

- [ ] Add caching layer for crypto prices
- [ ] Support more MCP servers (weather, news, etc.)
- [ ] Implement rate limiting per API
- [ ] Add user authentication
- [ ] WebSocket-based MCP transport
- [ ] Tool usage analytics dashboard
- [ ] Migration to official Aya API when available

## Contributing

This is a hackathon project, but contributions are welcome! Areas for improvement:

1. Add more crypto data sources
2. Implement additional MCP tools
3. Add unit tests for MCP client/server
4. Improve error messages
5. Add request caching


Built for the Aya Hackathon - demonstrating custom MCP implementation and tool-augmented AI agents.

---

**Star this repo** if you found the custom MCP implementation helpful!
