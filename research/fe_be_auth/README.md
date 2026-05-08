# FE-to-BE Authentication Flow — Research

## The Problem
The FE (Phoenix LiveView) calls the BE (Phoenix API) via Req (HTTP). How does the FE authenticate these server-side requests?

## Recommended Solution: Ueberauth on BE + Guardian JWT

### Flow
1. User visits FE, clicks "Login"
2. FE redirects browser to `BE_URL/auth/auth0` (standard HTTP redirect)
3. BE's Ueberauth plug redirects to Auth0
4. User authenticates at Auth0
5. Auth0 redirects to `BE_URL/auth/auth0/callback`
6. BE's callback: verifies token, upserts user, mints a Guardian JWT
7. BE redirects browser back to FE with the JWT as a query param or sets it in a cookie
8. FE stores the JWT in its Phoenix session (`put_session(conn, :be_token, jwt)`)
9. All subsequent Req calls from FE to BE include `Authorization: Bearer <jwt>`
10. BE's Authenticate plug verifies the Guardian JWT on each request

### Why This Works
- The browser handles the Auth0 redirect chain (FE → BE → Auth0 → BE → FE)
- The FE never talks to Auth0 directly — it just redirects the browser
- The BE owns authentication entirely
- The JWT is stored in the FE's server-side session (not in the browser)
- Req calls from FE to BE are server-to-server, carrying the JWT as a Bearer token

### Alternative Considered: Cookie-Based
The BE could set an HTTP-only cookie on the response after Auth0 callback. But since FE→BE calls are server-side (Req), not browser-side, cookies don't automatically carry. The FE would need to extract and forward cookies manually — messier than Bearer tokens.

### Alternative Considered: Distributed Erlang
Both apps connect as BEAM nodes. FE calls BE context functions directly via `:erpc`. No HTTP, no tokens. But this couples the apps and breaks the "replaceable FE" design goal. Deferred.

## Implementation Details

### BE Side (`:web` app)
```elixir
# Guardian implementation module
defmodule Web.Guardian do
  use Guardian, otp_app: :web

  def subject_for_token(%{id: id}, _claims), do: {:ok, to_string(id)}
  def resource_from_claims(%{"sub" => id}), do: {:ok, Core.Accounts.get_user!(id)}
end

# Auth callback — after Ueberauth succeeds
def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
  {:ok, user} = Core.Accounts.upsert_user(%{
    auth0_sub: auth.uid,
    email: auth.info.email,
    name: auth.info.name,
    picture: auth.info.image
  })
  {:ok, jwt, _claims} = Web.Guardian.encode_and_sign(user)
  
  redirect(conn, external: "#{fe_base_url}/auth/complete?token=#{jwt}")
end

# Authenticate plug for API routes
defmodule Web.Plugs.Authenticate do
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Web.Guardian.decode_and_verify(token),
         {:ok, user} <- Web.Guardian.resource_from_claims(claims) do
      assign(conn, :current_user, user)
    else
      _ -> conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end
end
```

### FE Side
```elixir
# AuthController handles the redirect back from BE
def complete(conn, %{"token" => token}) do
  conn
  |> put_session(:be_token, token)
  |> redirect(to: ~p"/dashboard")
end

# ApiClient attaches the token to every Req call
defmodule ArtemisHomeFe.ApiClient do
  def get(path, session) do
    Req.get("#{api_url()}#{path}",
      headers: [{"authorization", "Bearer #{session[:be_token]}"}]
    )
  end
end
```

## Token Lifecycle
- Guardian JWT TTL: 24 hours (configurable)
- On expiry: FE detects 401 response, redirects user to login again
- Future: add refresh tokens for seamless re-auth

## This Resolves
- Technical notes unresolved Q1: "FE-to-BE authentication — exact token flow"
- Technical notes unresolved Q2: "Auth0 token handling in FE"
