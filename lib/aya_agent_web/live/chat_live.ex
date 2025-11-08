defmodule AyaAgentWeb.ChatLive do
  use AyaAgentWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Connect to MCP server on mount
    connect_to_mcp_servers()

    socket =
      socket
      |> assign(:messages, [])
      |> assign(:form, to_form(%{"message" => ""}, as: :chat))
      |> assign(:loading, false)
      |> assign(:tools, get_available_tools())

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"chat" => %{"message" => message}}, socket) do
    if String.trim(message) == "" do
      {:noreply, socket}
    else
      # Add user message
      new_messages = socket.assigns.messages ++ [%{role: "user", content: message}]

      socket =
        socket
        |> assign(:messages, new_messages)
        |> assign(:form, to_form(%{"message" => ""}, as: :chat))
        |> assign(:loading, true)

      # Send to MCP Client (async)
      send(self(), {:send_to_llm, message})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:send_to_llm, message}, socket) do
    case McpClient.chat(message) do
      {:ok, response} ->
        new_messages = socket.assigns.messages ++ [%{role: "assistant", content: response}]

        socket =
          socket
          |> assign(:messages, new_messages)
          |> assign(:loading, false)

        {:noreply, socket}

      {:error, error} ->
        error_msg = "Error: #{inspect(error)}"
        new_messages = socket.assigns.messages ++ [%{role: "error", content: error_msg}]

        socket =
          socket
          |> assign(:messages, new_messages)
          |> assign(:loading, false)

        {:noreply, socket}
    end
  end

  defp connect_to_mcp_servers do
    case McpClient.add_mcp_server(:crypto, %{
           transport: :http,
           url: "http://localhost:4000"
         }) do
      {:ok, _tools} ->
        Logger.info("✅ Connected to Crypto MCP Server")

      {:error, reason} ->
        Logger.error("❌ Failed to connect: #{inspect(reason)}")
    end
  end

  defp get_available_tools do
    case McpClient.list_tools() do
      tools when is_list(tools) -> tools
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="chat-container" phx-hook="AutoScroll" id="chat-container">
        <style>
          .chat-container {
            max-width: 900px;
            margin: 0 auto;
            height: 100vh;
            display: flex;
            flex-direction: column;
            background: #1e293b;
          }
          .header {
            padding: 1.5rem;
            background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
            color: white;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
          }
          .header h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
          .tools-badge {
            display: inline-block;
            background: rgba(255,255,255,0.2);
            padding: 0.25rem 0.75rem;
            border-radius: 1rem;
            font-size: 0.875rem;
          }
          .messages {
            flex: 1;
            overflow-y: auto;
            padding: 2rem;
            display: flex;
            flex-direction: column;
            gap: 1rem;
          }
          .message {
            display: flex;
            gap: 1rem;
            max-width: 80%;
            animation: slideIn 0.3s ease-out;
          }
          @keyframes slideIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
          }
          .message.user {
            align-self: flex-end;
            flex-direction: row-reverse;
          }
          .message-avatar {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: bold;
            flex-shrink: 0;
          }
          .message.user .message-avatar {
            background: #6366f1;
            color: white;
          }
          .message.assistant .message-avatar {
            background: #10b981;
            color: white;
          }
          .message.error .message-avatar {
            background: #ef4444;
            color: white;
          }
          .message-content {
            background: #334155;
            padding: 1rem;
            border-radius: 1rem;
            color: #e2e8f0;
            line-height: 1.6;
            white-space: pre-wrap;
          }
          .message.user .message-content {
            background: #6366f1;
            color: white;
          }
          .message.error .message-content {
            background: #7f1d1d;
            color: #fecaca;
          }
          .input-area {
            padding: 1.5rem;
            background: #0f172a;
            border-top: 1px solid #334155;
          }
          .input-wrapper {
            display: flex;
            gap: 1rem;
            max-width: 100%;
          }
          input {
            flex: 1;
            padding: 1rem;
            border: 2px solid #334155;
            border-radius: 0.75rem;
            background: #1e293b;
            color: #e2e8f0;
            font-size: 1rem;
            outline: none;
            transition: border-color 0.2s;
          }
          input:focus { border-color: #6366f1; }
          button {
            padding: 1rem 2rem;
            background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
            color: white;
            border: none;
            border-radius: 0.75rem;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
          }
          button:hover:not(:disabled) {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.4);
          }
          button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
          }
          .loading {
            display: flex;
            gap: 0.5rem;
            padding: 1rem;
          }
          .loading-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #6366f1;
            animation: bounce 1.4s infinite ease-in-out;
          }
          .loading-dot:nth-child(2) { animation-delay: 0.2s; }
          .loading-dot:nth-child(3) { animation-delay: 0.4s; }
          @keyframes bounce {
            0%, 80%, 100% { transform: scale(0); }
            40% { transform: scale(1); }
          }
          .empty-state {
            text-align: center;
            color: #64748b;
            padding: 4rem 2rem;
          }
          .empty-state h2 { font-size: 1.5rem; margin-bottom: 1rem; }
        </style>

        <div class="header">
          <h1>🤖 Aya Agent - MCP Chat</h1>
          <span class="tools-badge">
            🛠️ {length(@tools)} tools available
          </span>
        </div>

        <div class="messages" id="messages-container">
          <%= if Enum.empty?(@messages) do %>
            <div class="empty-state">
              <h2>👋 Welcome to Aya Agent!</h2>
              <p>Ask me about cryptocurrency prices or anything else.</p>
              <p style="margin-top: 1rem; font-size: 0.875rem;">
                Try: "What's the price of Bitcoin?"
              </p>
            </div>
          <% else %>
            <%= for message <- @messages do %>
              <div class={"message #{message.role}"}>
                <div class="message-avatar">
                  <%= cond do %>
                    <% message.role == "user" -> %>
                      👤
                    <% message.role == "assistant" -> %>
                      🤖
                    <% message.role == "error" -> %>
                      ⚠️
                    <% true -> %>
                      💬
                  <% end %>
                </div>
                <div class="message-content">
                  {message.content}
                </div>
              </div>
            <% end %>

            <%= if @loading do %>
              <div class="message assistant">
                <div class="message-avatar">🤖</div>
                <div class="message-content">
                  <div class="loading">
                    <div class="loading-dot"></div>
                    <div class="loading-dot"></div>
                    <div class="loading-dot"></div>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <div class="input-area">
          <.form for={@form} phx-submit="send_message" class="input-wrapper" id="chat-form">
            <.input
              field={@form[:message]}
              type="text"
              placeholder="Ask me anything..."
              autocomplete="off"
              disabled={@loading}
              class="flex-1 px-4 py-3 border-2 border-gray-600 rounded-xl bg-gray-800 text-gray-200 text-base outline-none transition-colors focus:border-indigo-500"
            />
            <button type="submit" disabled={@loading}>
              {if @loading, do: "⏳ Sending...", else: "Send 🚀"}
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
