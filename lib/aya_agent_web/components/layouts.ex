defmodule AyaAgentWeb.Layouts do
  use AyaAgentWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <label tabindex="0" class="btn btn-ghost btn-sm gap-1">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="size-5"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M9.53 16.122a3 3 0 0 0-5.78 1.128 2.25 2.25 0 0 1-2.4 2.245 4.5 4.5 0 0 0 8.4-2.245c0-.399-.078-.78-.22-1.128Zm0 0a15.998 15.998 0 0 0 3.388-1.62m-5.043-.025a15.994 15.994 0 0 1 1.622-3.395m3.42 3.42a15.995 15.995 0 0 0 4.764-4.648l3.876-5.814a1.151 1.151 0 0 0-1.597-1.597L14.146 6.32a15.996 15.996 0 0 0-4.649 4.763m3.42 3.42a6.776 6.776 0 0 0-3.42-3.42"
          />
        </svg>
        Theme
      </label>
      <ul
        tabindex="0"
        class="dropdown-content menu p-2 shadow bg-base-200 rounded-box w-52 mt-4 z-[1]"
      >
        <li>
          <button phx-click={JS.dispatch("theme:set", detail: %{theme: "light"})}>
            Light
          </button>
        </li>
        <li>
          <button phx-click={JS.dispatch("theme:set", detail: %{theme: "dark"})}>
            Dark
          </button>
        </li>
        <li>
          <button phx-click={JS.dispatch("theme:set", detail: %{theme: "cupcake"})}>
            Cupcake
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
