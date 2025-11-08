defmodule AyaAgentWeb.PageController do
  use AyaAgentWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
