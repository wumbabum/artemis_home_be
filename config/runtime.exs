import Config

# Only env-var reading lives here. Anything static belongs in config.exs,
# dev.exs, test.exs, or prod.exs.

case config_env() do
  :test ->
    # test.exs supplies all values; runtime is a no-op so tests are
    # deterministic regardless of host env.
    :ok

  :dev ->
    # Dev is forgiving: anything missing falls back to a value that lets
    # `iex -S mix` and `mix phx.server` work without ceremony.
    # HA_BASE_URL / HA_TOKEN fall back to the existing direnv aliases
    # (HOME_ASSISTANT_URL / HOME_ASSISTANT_API_KEY) so SB12's renaming
    # is non-breaking for dev workflows.
    config :core,
      home_id: System.get_env("HOME_ID", "alpha"),
      auth0_domain: System.get_env("AUTH0_DOMAIN"),
      auth0_audience: System.get_env("AUTH0_AUDIENCE", "https://artemis.app/api"),
      auth0_m2m_client_id: System.get_env("AUTH0_M2M_CLIENT_ID"),
      auth0_m2m_client_secret: System.get_env("AUTH0_M2M_CLIENT_SECRET"),
      seed_admin_auth0_sub: System.get_env("SEED_ADMIN_AUTH0_SUB"),
      ha_base_url: System.get_env("HA_BASE_URL") || System.get_env("HOME_ASSISTANT_URL"),
      ha_token: System.get_env("HA_TOKEN") || System.get_env("HOME_ASSISTANT_API_KEY")

    port = "PORT" |> System.get_env("6565") |> String.to_integer()
    config :web, Web.Endpoint, http: [port: port]

    cors_origins =
      "CORS_ALLOWED_ORIGINS"
      |> System.get_env("http://localhost:6587")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    config :web, :cors_allowed_origins, cors_origins

    # DATABASE_URL is optional in dev; defaults fall back to dev.exs's
    # username/password/hostname/database. Override only when needed.
    if database_url = System.get_env("DATABASE_URL") do
      config :core, Core.Repo, url: database_url
    end

  :prod ->
    # Prod is strict: any missing required env var fails container startup.
    # We want misconfigured deployments to fail loud and fast at boot.
    config :core,
      home_id: System.fetch_env!("HOME_ID"),
      auth0_domain: System.fetch_env!("AUTH0_DOMAIN"),
      auth0_audience: System.fetch_env!("AUTH0_AUDIENCE"),
      auth0_m2m_client_id: System.fetch_env!("AUTH0_M2M_CLIENT_ID"),
      auth0_m2m_client_secret: System.fetch_env!("AUTH0_M2M_CLIENT_SECRET"),
      # Optional in prod — only the first-user-bootstrap path needs this.
      seed_admin_auth0_sub: System.get_env("SEED_ADMIN_AUTH0_SUB"),
      ha_base_url: System.fetch_env!("HA_BASE_URL"),
      ha_token: System.fetch_env!("HA_TOKEN")

    port = "PORT" |> System.get_env("6565") |> String.to_integer()

    config :web, Web.Endpoint,
      http: [port: port],
      url: [host: System.fetch_env!("PHX_HOST"), port: 443, scheme: "https"],
      secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
      server: true

    cors_origins =
      "CORS_ALLOWED_ORIGINS"
      |> System.fetch_env!()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    config :web, :cors_allowed_origins, cors_origins

    config :core, Core.Repo,
      url: System.fetch_env!("DATABASE_URL"),
      pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "10")),
      socket_options: [:inet6]
end
