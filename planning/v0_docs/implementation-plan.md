# Artemis v0 — Option D Proof of Concept

This document captures the architectural and technical choices for v0. Execution sequencing (commit order, dependencies between commits, pause points) is split into two per-repo docs: `step-by-step-commit-strat-be.md` for `artemis_home_be` and `step-by-step-commit-strat-fe.md` for `artemis_home_fe`. The BE sequence runs first; the FE sequence begins only after the BE is end-to-end validated.

## Problem Statement

Before committing to a full backend build, validate that Auth0 can serve as the identity hub described in Option D: a single Auth0 user holds a registry of home backends in `app_metadata`, custom claims surface that registry to the frontend, and each home BE independently verifies Auth0 JWTs via JWKS and issues its own home-scoped session tokens. v0 proves the architecture end-to-end without any home-automation features.

## Success Criteria

The PoC is successful when all of the following are demonstrated against a real Auth0 tenant:

- A test user has two homes registered in `app_metadata` (written via Management API)
- After login, the access token carries a `https://artemis.app/homes` custom claim listing both homes
- Two home BE instances (same code, different `HOME_ID` and port) run simultaneously and independently verify the Auth0 token against Auth0's JWKS
- Each home BE trades the Auth0 token for its own short-lived session JWT signed by that BE
- The FE logs in once, reads the homes list from `/userinfo`, calls each home BE's `/api/me/ping`, and displays both responses
- Logging in on a second browser/device shows the same home list (persistence is on Auth0's side, not the client)
- Multi-home is purely a frontend concern: the FE fans out to multiple isolated home BEs based on the Auth0 registry. Each BE has no knowledge of other BEs.

## Out of Scope for v0

Explicitly deferred to v1 or later:

- Home Assistant integration (REST or WebSocket)
- Device, room, schedule, guest key, or PAT data models
- Postgres (no Ecto in v0)
- MCP protocol implementation (the `:mcp` umbrella child app is a skeleton with no app code)
- Job scheduling (the `:dispatch` umbrella child app is a skeleton)
- LiveView, PWA manifest, service worker on the BE side (the FE has Tailwind in v0; the BE has no asset pipeline)
- Tailscale Funnel (everything runs on localhost)
- Cloak encryption (no secrets stored at rest in v0)
- Role/scope enforcement (a single "authenticated" check is enough)
- Invitations, email, SMS
- Multi-tenant data scoping in the BE (the `home_id` claim is asserted but no tenant-scoped data exists)

## Current State

- `artemis_home_be/` exists locally with three prior commits on `main` covering planning docs, research notes, and updates from live HA API tests. The `v0_docs/` directory (containing this file) is the only currently-uncommitted content.
- `artemis_home_fe/` exists locally with `.git/` only — no commits yet.
- Neither repo has a remote configured.
- Auth0 tenant is provisioned but the Application, API, M2M app, and Action are not yet configured.
- Live HA testing has been completed but is not used in v0.

## Decisions Locked In

1. **Multi-home is an FE pattern.** The FE holds the Auth0-issued registry of home BE URLs and fans out per-BE HTTP calls. Each home BE is isolated and has no concept of "other homes." Earlier research notes about `auth0_oidc/`, `fe_be_auth/`, and `pwa/` have been moved into the FE repo (`../../artemis_home_fe/planning/research/`) and rewritten for the React stack.
2. **`artemis_home_be` is an umbrella from day one.** Child apps: `:core`, `:dispatch`, `:mcp`, `:web`. `:dispatch` and `:mcp` are skeleton-only in v0 (default `mix new --sup` output plus a one-line `@moduledoc` describing future scope). All v0 functionality lives in `:core` and `:web`.
3. **`artemis_home_fe` is a React SPA**, not a Phoenix app. Lives in a separate repo with its own planning subtree (`artemis_home_fe/planning/`). See `../../artemis_home_fe/planning/v0_docs/implementation-plan.md` and `step-by-step-commit-strat-fe.md`.
4. **FE stack**: Vite + React 19 + TypeScript (strict) + Tailwind + Zustand + axios + `@auth0/auth0-react`. PKCE, no client secret in the browser. Deployed to Fly.io and runnable locally on Synology via Docker Compose. Details in the FE repo's implementation plan.
5. **Session token signing**: RS256 with a BE-generated RSA keypair persisted under `apps/core/priv/keys/`. Generated on first boot if missing. Same shape v1 will use.
6. **Auth0 tenant**: existing tenant. The single `artemis-home` Application is converted from Regular Web Application to Single Page Application (PKCE, no client secret). Bruno and the React SPA share this Application.
7. **Branch strategy**: feature branch `v0-poc` in both repos. No squash merge. PR merge after review.
8. **Testing posture for v0**: light-touch. Mocks live at layer boundaries (`:web` mocks `Core.Auth`; `Core.Auth` mocks its internal modules; the verifier itself is not unit-tested — Joken is assumed correct). Once the system works end-to-end against real Auth0, v1 will add real-data-driven tests.

## Tooling and Versions (BE)

- **Elixir**: 1.19 (latest)
- **Erlang/OTP**: latest stable (currently OTP 27)
- **Phoenix**: latest stable (1.7.x line)
- **.tool-versions**: committed at the umbrella root. The FE repo has its own `.tool-versions` pinning Node LTS — see `../../artemis_home_fe/planning/v0_docs/implementation-plan.md`.

## Library Choices (BE)

- HTTP client: `req ~> 0.5` (in `:core`)
- JWT signing and verification: `joken ~> 2.6` (in `:core`)
- JSON: `jason ~> 1.4` (in `:core`, `:web`)
- HTTP mocks for tests: `mox ~> 1.1` (in `:core` test environment)
- CORS: `cors_plug ~> 3.0` (in `:web`) — introduced in commit B9.5 to allow the React FE origin to call the BE.

Not used in v0: `guardian`, `cloak_ecto`, `oban`, `ecto`, `dotenvy`, `pow`, `phoenix_live_view`, `tailwind`, `esbuild` beyond defaults, `ueberauth` (no FE OAuth handshake on the BE side; the React SPA handles PKCE on the client and posts the resulting access token directly).

FE library choices live in `../../artemis_home_fe/planning/v0_docs/implementation-plan.md`.

## Repository Layout

```
artemis_home_be/                  # umbrella
├── apps/
│   ├── core/                     # auth context, Auth0 wrappers, session key/token (v0)
│   ├── dispatch/                 # skeleton (Oban-based scheduling lives here in v1)
│   ├── mcp/                      # skeleton (MCP protocol handler lives here in v1)
│   └── web/                      # Phoenix JSON API (no Ecto, no HTML)
├── config/
├── planning/                     # existing v1 planning docs
│   └── v0_docs/                  # this folder
└── ...
```

The FE repo (`artemis_home_fe/`) is structured independently. See
`../../artemis_home_fe/planning/v0_docs/implementation-plan.md` for its tree.

## Umbrella Scaffolding (BE)

Per the Phoenix Umbrella Scaffolding personal rule, the BE scaffold uses dedicated generators run from the umbrella root for naming control:

- `mix new artemis_home_be --umbrella`
- From the umbrella root:
  - `mix new apps/core --sup`
  - `mix new apps/dispatch --sup`
  - `mix new apps/mcp --sup`
  - `mix phx.new.web apps/web --adapter cowboy --no-ecto --no-mailer --no-html --no-assets --no-dashboard --no-live`

Notes from the rule that apply here:

- `--no-ecto` on `phx.new.web` omits `{Phoenix.PubSub, name: Web.PubSub}` from the supervision tree. Add it manually.
- The web app has no `ecto_repos` config.
- A `.tool-versions` file is committed at the umbrella root.
- Child app modules are unprefixed: `Core`, `Web`, `Dispatch`, `Mcp` (not `ArtemisHomeBe.Core`).

Pow is not used in v0; the `phx.gen.auth`/Pow notes in the rule do not apply.

## Auth0 Configuration

Tenant is already provisioned. One Application, type **Single Page Application**:

- `client_id`: `VASJGlxmKdJdGcsqMbXIMCmO47QxEB9x` (existing; converted from RWA).
- No client secret. Token Endpoint Authentication Method: `None`. PKCE required.
- **Allowed Callback URLs**: `http://localhost:8765/callback` (Bruno), `http://localhost:6587/callback` (React FE dev), `https://artemis-home.fly.dev/callback` (React FE prod).
- **Allowed Logout URLs**: `http://localhost:6587`, `https://artemis-home.fly.dev`.
- **Allowed Web Origins**: `http://localhost:6587`, `https://artemis-home.fly.dev`.
- **Refresh Token Rotation**: enabled. Reuse interval: 0 seconds. Absolute expiration: 30 days.

Bruno and the React SPA both drive this Application via Authorization Code + PKCE — Bruno as the manual POC driver, the React SPA programmatically. The BE has no awareness of the client distinction; it only verifies the resulting JWT's `iss`, `aud`, `exp`, and signature.

Shared tenant resources:

- **API**: `https://artemis-home.fly.dev` (audience used by all home BEs). Identifier is URL-shaped but does not imply a particular FE deployment target.
- **M2M Application**: separate Application, scoped to `read:users`, `update:users_app_metadata` for Management API writes.
- **Post-Login Action** injects the homes claim into both the ID token and the access token so the FE can read it via `/userinfo` without decoding any JWT itself:

```js
exports.onExecutePostLogin = async (event, api) => {
  const homes = event.user.app_metadata?.homes || [];
  api.idToken.setCustomClaim("https://artemis.app/homes", homes);
  api.accessToken.setCustomClaim("https://artemis.app/homes", homes);
};
```

- Test user: one human-readable account, seeded with two `homes` entries pointing to `http://localhost:6565` (alpha) and `http://localhost:6566` (beta).

## Key Material

Two independent RSA key pairs are involved. They are not shared.

- **Auth0 signing key** (Auth0-owned): signs every Auth0-issued token. BE fetches the public key from `https://YOUR_TENANT.auth0.com/.well-known/jwks.json`, caches it keyed by `kid`, and refreshes on miss. BE never sees the private half.
- **BE session signing key** (BE-owned): RS256 keypair generated by the BE on first startup if missing, persisted at `apps/core/priv/keys/session_signing.pem` (private) and `apps/core/priv/keys/session_signing.pub.pem` (public). BE both signs and verifies its own session JWTs. The FE never decodes session JWTs — it stores them as opaque bearer tokens.

Neither key is consumed by the FE.

## Backend Architecture (`artemis_home_be`)

### `:core` — auth context and external wrappers

All v0 BE business logic lives here. The `:web` app talks only to the public `Core.Auth` API; it does not import `Core.Auth.*` internals directly.

- `apps/core/lib/core/auth.ex` — public context API:
  - `exchange_auth0_token(token, home_id) :: {:ok, %{user_sub, home_id, session_jwt}} | {:error, reason}`
  - `verify_session(token) :: {:ok, claims} | {:error, reason}`
  - `register_home_for_user(user_sub, home_id, url) :: {:ok, _} | {:error, reason}`
- `apps/core/lib/core/auth/jwks_cache.ex` — behaviour + GenServer impl. Caches Auth0 JWKS by `kid`; refreshes on cache miss.
- `apps/core/lib/core/auth/auth0_verifier.ex` — Joken-based verifier. Validates `iss`, `aud`, `exp`, RS256 signature against `JwksCache`. Additionally asserts that this BE's `HOME_ID` appears in the `https://artemis.app/homes` claim. The `aud` check uses the audience set in `AUTH0_AUDIENCE` (`https://artemis-home.fly.dev`).
- `apps/core/lib/core/auth/session_signing_key.ex` — loads RSA keypair from `priv/keys/`; generates and persists on first boot if absent.
- `apps/core/lib/core/auth/session_token.ex` — issues and verifies RS256 session JWTs (`sub`, `home_id`, `exp`, `iat`); short TTL (1 hour).
- `apps/core/lib/core/auth/management_api.ex` — Req wrapper around `PATCH /api/v2/users/:id`. Acquires M2M token on demand and caches it briefly.
- `apps/core/lib/mix/tasks/seed_homes.ex` — mix task implementation; wired to a root alias `seed.homes`.

### `:web` — Phoenix JSON API

Pure web layer. No business logic.

- `apps/web/lib/web/router.ex` — three routes:
  - `POST /api/sessions`
  - `GET  /api/me/ping` (under `:authenticated` pipeline)
  - `POST /api/admin/register-home`
- `apps/web/lib/web/plugs/require_session.ex` — extracts bearer token, calls `Core.Auth.verify_session/1`, assigns `:current_user`.
- `apps/web/lib/web/controllers/session_controller.ex` — `create/2` calls `Core.Auth.exchange_auth0_token/2`.
- `apps/web/lib/web/controllers/me_controller.ex` — `ping/2` returns `{home_id, user_sub, role: "admin"}`.
- `apps/web/lib/web/controllers/admin_controller.ex` — `register_home/2` calls `Core.Auth.register_home_for_user/3`.

### `:dispatch` and `:mcp` — skeleton-only

Each contains only the default output of `mix new apps/<name> --sup` plus a single-line `@moduledoc` describing its v1 purpose. They exist in the supervision tree but start nothing. They prove the umbrella structure for v1 without carrying v0 weight.

### Runtime configuration (BE)

`config/runtime.exs` uses `case config_env() do` to read env vars differently per environment. Static config lives in `config.exs`, `dev.exs`, `test.exs`, or `prod.exs` — only env-var reading belongs in `runtime.exs`.

- `:test` — no-op. `test.exs` supplies all values so test runs are deterministic regardless of host env.
- `:dev` — `System.get_env(name, default)` with forgiving defaults so `iex -S mix` and `mix phx.server` work without ceremony.
- `:prod` — `System.fetch_env!(name)` for every required var. Missing values fail container boot loudly and fast. Running as a Docker container always means `MIX_ENV=prod`.

Required env vars (must be set in prod):

- `HOME_ID` — identifies this BE instance (`alpha`, `beach_house`, ...). Must match an entry in the Auth0 user's `app_metadata.homes`.
- `PHX_HOST` — public hostname Phoenix uses for URL generation.
- `SECRET_KEY_BASE` — Phoenix session/cookie signing. Generate with `mix phx.gen.secret`.
- `AUTH0_DOMAIN` — e.g. `your-tenant.us.auth0.com`.
- `AUTH0_AUDIENCE` — `https://artemis-home.fly.dev`.
- `AUTH0_M2M_CLIENT_ID`, `AUTH0_M2M_CLIENT_SECRET` — Management API credentials, used by `Core.Auth.ManagementApi` and the `mix seed.homes` task.

Optional env vars (defaulted):

- `PORT` — defaults to `4000`. Inside the container we bind to a known port; Synology Project Manager maps host port → container port via `ports:`.
- `TZ` — container timezone for log timestamps.

## Frontend Architecture (`artemis_home_fe`)

See `../../artemis_home_fe/planning/v0_docs/implementation-plan.md`. Summary for context:

- React 19 SPA, Vite + TypeScript (strict) + Tailwind.
- `@auth0/auth0-react` with PKCE and `useRefreshTokens: true`.
- Zustand stores for the Auth0 access token (`authStore`) and per-home session JWTs (`sessionStore`), both in memory only.
- axios client with request/response interceptors handling Bearer injection and `401 → silent renew → retry`.
- Dashboard fans out per-home `createSession` + `ping` calls via `Promise.allSettled`.
- Deployed to Fly.io at `https://artemis-home.fly.dev/`; runnable locally on Synology via Docker Compose.

The FE performs zero JWT decoding in application code. All JWT handling lives on the BE.

## Testing Posture

- **Layer boundary mocking**: `:web` controller tests mock `Core.Auth` via Mox. `Core.Auth` tests mock its internal modules (`JwksCache`, `Auth0Verifier`, `SessionToken`, `ManagementApi`) via Mox.
- **No tests for the verifier internals**: Joken is treated as a trusted dependency. Behaviour-level assertions live in `Core.Auth` tests.
- **One happy-path test per module**: each public function gets at least one happy-path assertion. Error paths are covered only where the error shape differs structurally.
- **Manual end-to-end validation**: smoke tests against a real Auth0 tenant are scheduled at specific pause points (see `step-by-step-commit-strat-be.md` and `step-by-step-commit-strat-fe.md`).
- **What v1 adds**: real-Auth0-fixture-driven property tests, full error-path coverage, integration tests that run alpha and beta concurrently.

## Risks and Unknowns

- **JWKS verification correctness** — easy to mis-validate `iss`/`aud`. Mitigation: smoke test against a real Auth0 token captured from a browser session, not unit fixtures.
- **Token size with custom claim** — for v0 with two homes the claim is trivially small. Document the ~8 KB header threshold for v1.
- **Management API rate limits** — Auth0's dev tenant caps Management API calls per day. For v0 we expect <10 writes total.
- **Audience handling across multiple home BEs** — a single audience (`https://artemis-home.fly.dev`) is shared by all home BEs. Each BE additionally checks `home_id` to confirm the token was meant for it. v1 must not accidentally introduce per-home audiences.
- **Local HTTPS** — Auth0 accepts `http://localhost` for dev. No mkcert needed for v0.
- **PubSub omission from `phx.new.web --no-ecto`** — must be added manually to the web app's supervision tree.
- **CORS misconfiguration** — the React SPA runs on a different origin from each home BE in v0 (`localhost:6587` → `localhost:6565`/`6566`). Each home BE must allow the FE origin via `CORSPlug` (B9.5). A new home added later without CORS configured will silently break the FE; v1 should add a setup check.
- **Access tokens in the browser** — Auth0 access tokens live in the SPA's JS heap. Any XSS that runs in the SPA context can exfiltrate them. Mitigations are FE-side (CSP header on nginx, dependency audits, no `eval()` in app code); BE accepts the resulting exposure and relies on token TTL to bound damage.
- **Bundle-build cache invalidation on Fly** — the FE bakes `VITE_*` env vars into the bundle at build time. Changing audience/domain requires a new deploy. v0 has only one Fly app, so the risk is contained.

## Deployment Artifacts

For production deployment (Synology Container Manager or any Compose-aware host), v0 ships two artifacts at the umbrella root:

- `docker-compose.yml` — sample service definition. Required env vars use `${VAR:?message}` so Docker Compose itself errors out at evaluation time if any are unset. Optional vars use `${VAR:-default}`. The single bind mount maps a host path (default `./keys`) to `/app/apps/core/priv/keys` so the BE's RSA session signing key survives container restarts.
- `.env.example` — documents every variable the compose file references. Users copy it to `.env` (gitignored) and fill in real values.

The image itself (`Dockerfile`, multi-stage release build, push to Docker Hub) is deferred to a later v0 commit or to v1. The runtime config is already prod-ready via `fetch_env!`.

v0 itself runs locally with `mix phx.server`. Docker artifacts are forward-compatibility templates so the container deployment story is ready when we want to use it.

## What v1 Inherits from v0

If the PoC succeeds, v1 reuses verbatim:

- The entire `Core.Auth` module tree (JwksCache, Auth0Verifier, SessionSigningKey, SessionToken, ManagementApi, public context API).
- The BE-owned RSA keypair on disk (same path, same algorithm).
- The umbrella structure with `:core`, `:dispatch`, `:mcp`, `:web`.
- The `/api/sessions` exchange pattern.
- The home registry shape in `app_metadata`.
- The Auth0 Post-Login Action.
- The CORS plug (B9.5) — carries forward with an updated allow-list.
- The entire React SPA codebase. v0 is the seed of the v1 client, not throwaway scaffolding. The FE plan in `../../artemis_home_fe/planning/v0_docs/implementation-plan.md` lists FE specifics.

v1 extends with: Ecto + Postgres for users/home_memberships/devices/schedules, role/scope enforcement, HA REST and WebSocket integration in `:core` and `:dispatch`, the MCP protocol in `:mcp`, polished UI on top of the React SPA, PWA manifest + service worker, Tailscale Funnel deployment, Cloak field encryption, Oban for schedule execution, and (in v2) KMM-shared business logic with Kotlin/Swift native shells.
