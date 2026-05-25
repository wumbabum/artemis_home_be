import Config

# Core.Repo test config. Sandbox pool: each test runs in its own
# transaction and rolls back on exit, keeping tests isolated.
config :core, Core.Repo,
  username: "postgres",
  password: "",
  hostname: "localhost",
  database: "artemis_home_be_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :web, Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "93URhZRAlAMxJ+cT739IpoR86AgLVeM2s/iETGlEKYSRAuPmJ4KIJ3GKpiJrTTIJ",
  server: false

# Swap external dependencies for Mox-backed mocks during tests.
config :core, :jwks_fetcher, Core.Auth.JwksCache.HttpFetcherMock
config :core, :jwks_cache, Core.Auth.JwksCacheMock
config :core, :management_api_http_client, Core.Auth.ManagementApi.HttpClientMock

# Core.Auth picks its collaborators by config so it can be unit-tested with
# Mox while the real implementations remain testable directly.
config :core, :auth0_verifier, Core.Auth.Auth0VerifierMock
config :core, :session_token, Core.Auth.SessionTokenMock
config :core, :management_api, Core.Auth.ManagementApiMock
config :core, :ha_rest_client, Core.HA.RestClientMock

# Tests own the StateCache lifecycle explicitly via `start_supervised!`
# with isolated names. The supervisor-started default would collide
# on the `:cover_state` ETS table.
config :core, :start_state_cache, false

# Test defaults for env-driven settings normally provided at runtime.
config :core,
  home_id: "test_home",
  auth0_domain: "test.auth0.com",
  auth0_audience: "https://artemis.app/api",
  auth0_m2m_client_id: "test_m2m_client_id",
  auth0_m2m_client_secret: "test_m2m_client_secret",
  seed_admin_auth0_sub: "google-oauth2|test-admin-sub",
  ha_base_url: "http://homeassistant.test/api",
  ha_token: "test_ha_token"

config :web, :cors_allowed_origins, ["http://localhost:6587"]
