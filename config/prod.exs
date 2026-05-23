import Config

# Static prod endpoint settings. All env-driven values (PHX_HOST,
# SECRET_KEY_BASE, PORT, etc.) live in runtime.exs.

# Bind to all interfaces (IPv6) so the container accepts traffic from the host.
config :web, Web.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Force SSL via x-forwarded-proto from whatever reverse proxy fronts the
# container (Tailscale Funnel, Cloudflare Tunnel, nginx, etc.). `force_ssl`
# must be set at compile-time per Phoenix docs.
config :web, Web.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: ["localhost"]
  ]
