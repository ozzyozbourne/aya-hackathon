import Config

config :aya_agent, AyaAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AyaAgentWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: AyaAgent.PubSub,
  live_view: [signing_salt: "random_salt_here"],
  secret_key_base: "your_secret_key_base_here_make_it_long_and_random",
  debug_errors: true,
  code_reloader: true,
  check_origin: false

config :phoenix, :json_library, Jason

config :esbuild,
  version: "0.25.0",
  aya_agent: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.12",
  aya_agent: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
