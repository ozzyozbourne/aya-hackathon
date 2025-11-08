defmodule AyaAgent.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # ✅ Added PubSub
      {Phoenix.PubSub, name: AyaAgent.PubSub},
      # Start the MCP Client
      McpClient,
      # Start Phoenix Endpoint
      AyaAgentWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AyaAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AyaAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
