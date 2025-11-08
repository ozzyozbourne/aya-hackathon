defmodule McpClient do
  use GenServer
  require Logger

  @gemini_api_key System.get_env("GEMINI_API_KEY") ||
                    raise("""
                    Missing GEMINI_API_KEY environment variable!
                    Please set it before compiling, e.g.:

                        export GEMINI_API_KEY="your_api_key_here"
                    """)
  @gemini_api_url "https://generativelanguage.googleapis.com/v1beta/models"

  defstruct [
    :mcp_servers,
    :available_tools,
    :conversation_history
  ]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def add_mcp_server(server_name, server_config),
    do: GenServer.call(__MODULE__, {:add_mcp_server, server_name, server_config})

  def chat(message), do: GenServer.call(__MODULE__, {:chat, message}, 30_000)
  def list_tools, do: GenServer.call(__MODULE__, :list_tools)

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      mcp_servers: %{},
      available_tools: [],
      conversation_history: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_mcp_server, server_name, config}, _from, state) do
    case connect_to_mcp_server(server_name, config) do
      {:ok, server_info} ->
        new_servers = Map.put(state.mcp_servers, server_name, server_info)
        new_tools = fetch_tools_from_server(server_name, server_info)

        new_state = %{
          state
          | mcp_servers: new_servers,
            available_tools: state.available_tools ++ new_tools
        }

        Logger.info("✅ Connected to MCP server: #{server_name}")
        Logger.info("📦 Loaded #{length(new_tools)} tools from #{server_name}")

        {:reply, {:ok, new_tools}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    {:reply, state.available_tools, state}
  end

  @impl true
  def handle_call({:chat, message}, _from, state) do
    Logger.info("💬 User: #{message}")

    new_history =
      state.conversation_history ++
        [%{role: "user", parts: [%{text: message}]}]

    case call_gemini_with_tools(new_history, state.available_tools, state.mcp_servers) do
      {:ok, response, updated_history} ->
        Logger.info("🤖 Gemini: #{response}")
        new_state = %{state | conversation_history: updated_history}
        {:reply, {:ok, response}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_server_info, _from, state) do
    {:reply, {:ok, state.mcp_servers}, state}
  end

  defp connect_to_mcp_server(server_name, config) do
    case config[:transport] do
      :http ->
        connect_http_server(server_name, config)

      _ ->
        {:error, "Unsupported transport type"}
    end
  end

  defp connect_http_server(_server_name, config) do
    url = config[:url]
    # For HTTP/SSE MCP servers
    {:ok, %{url: url, transport: :http}}
  end

  defp fetch_tools_from_server(server_name, server_info) do
    list_tools_request = %{
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list",
      params: %{}
    }

    case call_mcp_server(server_info, list_tools_request) do
      {:ok, response} ->
        tools = get_in(response, ["result", "tools"]) || []

        # Add server_name to each tool so we know which server to call
        Enum.map(tools, fn tool ->
          Map.put(tool, "server_name", server_name)
        end)

      {:error, _} ->
        []
    end
  end

  defp call_mcp_server(%{transport: :http, url: url}, request) do
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, Jason.encode!(request), headers) do
      {:ok, %{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_gemini_with_tools(conversation_history, available_tools, mcp_servers) do
    model = "gemini-2.0-flash-exp"
    url = "#{@gemini_api_url}/#{model}:generateContent?key=#{@gemini_api_key}"

    request_body =
      if length(available_tools) > 0 do
        gemini_tools = convert_mcp_tools_to_gemini(available_tools)

        %{
          contents: conversation_history,
          tools: [%{function_declarations: gemini_tools}]
        }
      else
        %{contents: conversation_history}
      end

    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, Jason.encode!(request_body), headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} ->
            handle_gemini_response(response, conversation_history, available_tools, mcp_servers)

          {:error, _} ->
            {:error, "Failed to parse Gemini response"}
        end

      {:ok, %{status_code: status, body: body}} ->
        {:error, "Gemini API error #{status}: #{body}"}

      {:error, %{reason: reason}} ->
        {:error, "Network error: #{reason}"}
    end
  end

  defp handle_gemini_response(response, history, tools, mcp_servers) do
    candidate = List.first(response["candidates"])
    content = candidate["content"]
    parts = content["parts"]

    # Check if Gemini wants to call a function
    function_call = Enum.find(parts, fn part -> Map.has_key?(part, "functionCall") end)

    if function_call do
      # Gemini wants to use a tool
      fc = function_call["functionCall"]
      function_name = fc["name"]
      arguments = fc["args"]

      Logger.info("🔧 Gemini calling tool: #{function_name}")
      Logger.info("Arguments: #{inspect(arguments)}")

      # Find which MCP server has this tool
      tool = Enum.find(tools, fn t -> t["name"] == function_name end)

      if tool do
        server_name = tool["server_name"]

        # Call the MCP server
        case execute_tool_on_mcp_server(server_name, function_name, arguments, mcp_servers) do
          {:ok, result} ->
            Logger.info("✅ Tool result: #{inspect(result)}")

            # Send function result back to Gemini
            new_history =
              history ++
                [
                  content,
                  %{
                    role: "user",
                    parts: [
                      %{
                        functionResponse: %{
                          name: function_name,
                          response: %{result: result}
                        }
                      }
                    ]
                  }
                ]

            # Get final response from Gemini
            call_gemini_with_tools(new_history, tools, mcp_servers)

          {:error, error} ->
            {:error, "Tool execution failed: #{error}"}
        end
      else
        {:error, "Tool not found: #{function_name}"}
      end
    else
      # Gemini returned a text response
      text_part = Enum.find(parts, fn part -> Map.has_key?(part, "text") end)
      final_text = text_part["text"]

      # Update conversation history
      final_history = history ++ [content]

      {:ok, final_text, final_history}
    end
  end

  defp execute_tool_on_mcp_server(server_name, tool_name, arguments, mcp_servers) do
    # Get server info from passed state instead of GenServer.call
    server_info = Map.get(mcp_servers, server_name)

    if server_info do
      # Call tools/call on MCP server
      tool_call_request = %{
        jsonrpc: "2.0",
        id: :rand.uniform(10000),
        method: "tools/call",
        params: %{
          name: tool_name,
          arguments: arguments
        }
      }

      case call_mcp_server(server_info, tool_call_request) do
        {:ok, response} ->
          result = get_in(response, ["result", "content"])
          # Extract text from content array
          text =
            result
            |> List.first()
            |> Map.get("text", "")

          {:ok, text}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Server not found: #{server_name}"}
    end
  end

  defp convert_mcp_tools_to_gemini(mcp_tools) do
    Enum.map(mcp_tools, fn tool ->
      %{
        name: tool["name"],
        description: tool["description"],
        parameters: tool["inputSchema"]
      }
    end)
  end
end

defmodule AyaAgent.CLI do
  def start do
    IO.puts("""
    🚀 Starting Aya Agent with Gemini Flash + MCP
    ============================================
    """)

    {:ok, _} = McpClient.start_link([])

    IO.puts("📡 Connecting to MCP servers...")

    case McpClient.add_mcp_server(:crypto, %{
           transport: :http,
           url: "http://localhost:4000"
         }) do
      {:ok, tools} ->
        IO.puts("✅ Connected to Crypto MCP Server")
        IO.puts("📦 Loaded #{length(tools)} tools\n")

      {:error, reason} ->
        IO.puts("❌ Failed to connect to Crypto MCP Server: #{inspect(reason)}")
    end

    case McpClient.list_tools() do
      tools when is_list(tools) ->
        Enum.each(tools, fn tool ->
          IO.puts("   • #{tool["name"]}: #{tool["description"]}")
        end)

      _ ->
        IO.puts("   No tools available")
    end

    IO.puts("\n💬 Start chatting! (type 'exit' to quit)\n")
    chat_loop()
  end

  defp chat_loop do
    message = IO.gets("You: ") |> String.trim()

    case message do
      "exit" ->
        IO.puts("👋 Goodbye!")
        :ok

      "" ->
        chat_loop()

      _ ->
        case McpClient.chat(message) do
          {:ok, response} ->
            IO.puts("Aya: #{response}\n")

          {:error, error} ->
            IO.puts("❌ Error: #{error}\n")
        end

        chat_loop()
    end
  end
end
