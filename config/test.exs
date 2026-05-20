import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :web, Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "93URhZRAlAMxJ+cT739IpoR86AgLVeM2s/iETGlEKYSRAuPmJ4KIJ3GKpiJrTTIJ",
  server: false

# Swap external dependencies for Mox-backed mocks during tests.
config :core, :jwks_fetcher, Core.Auth.JwksCache.HttpFetcherMock
