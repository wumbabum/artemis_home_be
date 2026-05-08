# Auth0 OIDC in Elixir — Research

## Two Approaches

### Option 1: Ueberauth + ueberauth_auth0 (Recommended)
**Library:** `ueberauth` ~> 0.10 + `ueberauth_auth0` ~> 2.1

Full plug-based OAuth2 strategy. Handles redirect, callback, token exchange, and user info extraction automatically. Well-maintained, Auth0-specific.

Config:
```elixir
# config.exs
config :ueberauth, Ueberauth,
  providers: [
    auth0: {Ueberauth.Strategy.Auth0, [default_scope: "openid profile email"]}
  ]

config :ueberauth, Ueberauth.Strategy.Auth0.OAuth,
  domain: System.get_env("AUTH0_DOMAIN"),
  client_id: System.get_env("AUTH0_CLIENT_ID"),
  client_secret: System.get_env("AUTH0_CLIENT_SECRET")
```

Controller:
```elixir
defmodule Web.AuthController do
  use Web, :controller
  plug Ueberauth

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # auth.uid = Auth0 sub
    # auth.info.email, auth.info.name, auth.info.image
    # auth.credentials.token = access_token
    # auth.credentials.other.id_token = JWT
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    # handle failure
  end
end
```

Routes: `GET /auth/auth0` (request phase), `GET /auth/auth0/callback` (callback)

**Pros:** Battle-tested, handles CSRF state, extracts user info, works with Phoenix plugs.
**Cons:** Adds ueberauth as a dependency. Callback lives on the BE, so the FE needs to redirect to BE for login.

### Option 2: Direct JOSE + Req (Manual)
**Libraries:** `jose` ~> 1.11, `req` ~> 0.5

Build the OAuth2 flow manually. More control, fewer dependencies, but more code to maintain.

Steps:
1. Generate authorization URL with state param
2. Redirect user to Auth0
3. Receive callback with code
4. Exchange code for tokens via `POST https://{domain}/oauth/token`
5. Verify ID token JWT against JWKS at `https://{domain}/.well-known/jwks.json`
6. Extract claims (sub, email, name, picture)

The existing `home_assist_ex` app already has this partially implemented in `authenticator.ex` — but it uses `:httpc` instead of Req and has some issues (duplicate function definitions).

**Pros:** No ueberauth dependency, full control, smaller footprint.
**Cons:** Must handle CSRF state, JWKS caching, token validation manually. More error-prone.

## Recommendation for Artemis

**Use Ueberauth on the BE (`:web` app).** The FE redirects the browser to the BE's `/auth/auth0` route, which redirects to Auth0. After auth, Auth0 redirects back to the BE's callback, which verifies the token, upserts the user, creates a session, and redirects back to the FE.

This means the Auth0 callback URL is on the BE, not the FE. The FE's role is just to initiate the flow by linking to the BE's auth route.

## Additional: Guardian for Session Tokens

After Auth0 authenticates the user, the BE needs to issue its own session token for FE→BE API calls. **Guardian** (~> 2.3) is the standard Elixir library for this:

- `encode_and_sign(user)` → JWT token
- `decode_and_verify(token)` → claims
- Plug pipelines for protecting routes
- Token refresh and revocation

The FE stores the Guardian-issued JWT in its session and passes it as `Authorization: Bearer <token>` in Req calls to the BE.

## Dependencies Summary
- BE: `ueberauth`, `ueberauth_auth0`, `guardian`, `jose`
- FE: none (just redirects to BE auth routes)
