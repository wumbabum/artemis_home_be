# artemis_home_be

Elixir/Phoenix umbrella backend for Artemis, a multi-home automation
system. Each home runs its own isolated BE instance; users authenticate
once against Auth0 and the frontend fans out to every home in their
Auth0 `app_metadata.homes` registry.

This is the **v0 proof of concept**. It validates the Auth0-as-identity-hub
architecture end-to-end without any home-automation features. The full
architectural rationale lives in `planning/v0_docs/implementation-plan.md`.

The React FE that drives this BE lives in a sibling repo,
`artemis_home_fe`.

## Status

- v0 BE feature work is complete through pause point B-γ.
- v0 web layer exposes `POST /api/sessions`, `GET /api/me/ping`, and
  `POST /api/admin/register-home`. All routes require Auth0 to be
  configured (see below).
- No HA / device / room features yet; deferred to v1.

## Repository layout

```
artemis_home_be/                    # umbrella root
├── apps/
│   ├── core/                       # auth context, Auth0 wrappers, session keys (v0)
│   ├── dispatch/                   # skeleton; Oban scheduling lives here in v1
│   ├── mcp/                        # skeleton; MCP protocol handler lives here in v1
│   └── web/                        # Phoenix JSON API (no Ecto, no HTML)
├── config/                         # umbrella-wide configuration
├── planning/                       # v0 and v1 planning docs (tracked)
│   └── v0_docs/
│       ├── implementation-plan.md
│       └── step-by-step-commit-strat-be.md
├── docker-compose.yml              # Synology / Compose deployment template
├── .env.example                    # documented runtime env vars
└── README.md                       # this file
```

## Prerequisites

- Elixir 1.19 / Erlang OTP 28 (pinned via `.tool-versions`).
- Phoenix 1.8.x (resolved automatically by `mix deps.get`).
- Auth0 tenant with:
  - A **Single Page Application** for browser/Bruno login
    (Authorization Code + PKCE, no client secret).
  - An **API** resource whose Identifier matches `AUTH0_AUDIENCE`.
  - A **Machine to Machine Application** authorized for the Auth0
    Management API with scopes `read:users` and `update:users_app_metadata`.
  - A **Post-Login Action** that copies `event.user.app_metadata.homes`
    onto the `https://artemis.app/homes` custom claim of both the
    access token and the ID token. Full snippet in
    `planning/v0_docs/implementation-plan.md` §Auth0 Configuration.
- Docker (Compose v2) only if you intend to run via the deployment
  template instead of `mix phx.server`.

## Environment variables

Copy `.env.example` to `.env` and fill in real values. `.env` is
gitignored. Variables fall into three groups:

- **Required at boot (`:prod`):** `HOME_ID`, `PHX_HOST`,
  `SECRET_KEY_BASE`, `AUTH0_DOMAIN`, `AUTH0_M2M_CLIENT_ID`,
  `AUTH0_M2M_CLIENT_SECRET`, `CORS_ALLOWED_ORIGINS`. Missing values
  fail container startup loud and fast.
- **Defaulted:** `AUTH0_AUDIENCE` (defaults to
  `https://artemis.app/api`), `PORT` (defaults to `6565`),
  `HOST_PORT` (host-side port mapping in Compose, defaults to `6565`),
  `KEYS_PATH` (host path mounted for RSA session signing keys),
  `TZ` (container timezone).
- **Test:** test config in `config/test.exs` supplies all values
  itself; `runtime.exs` is a no-op in `:test`.

Full table with descriptions is in
`planning/v0_docs/implementation-plan.md` §Runtime configuration (BE).

## Running locally (two-home dev setup)

The v0 PoC demonstrates multi-home fan-out, so the standard local
setup runs **two BE instances simultaneously** with different
`HOME_ID` and `PORT`. Each terminal:

```bash
# Terminal 1 — "alpha"
HOME_ID=alpha PORT=6565 \
AUTH0_DOMAIN=your-tenant.us.auth0.com \
AUTH0_AUDIENCE=https://artemis-home.fly.dev \
AUTH0_M2M_CLIENT_ID=... \
AUTH0_M2M_CLIENT_SECRET=... \
  mix phx.server

# Terminal 2 — "beta"
HOME_ID=beta PORT=6566 \
  (same Auth0 vars) \
  mix phx.server
```

The two instances share the BE codebase but are independent at
runtime: separate `priv/keys/session_signing.pem` keypairs, separate
in-memory JWKS caches, and they each reject tokens whose homes claim
doesn't list their own `HOME_ID`.

## Seeding homes for a test user

Before the FE can fan out, a user's `app_metadata.homes` must contain
the `{home_id, url}` entries. Use the `seed.homes` mix task with M2M
credentials exported in your shell:

```bash
export AUTH0_DOMAIN=your-tenant.us.auth0.com
export AUTH0_M2M_CLIENT_ID=...
export AUTH0_M2M_CLIENT_SECRET=...

mix seed.homes \
  --user-sub "google-oauth2|..." \
  --home alpha:http://localhost:6565 \
  --home beta:http://localhost:6566
```

The task is read-modify-write so repeated invocations accumulate.
Full doc: `mix help seed.homes`.

## Smoke-testing the HTTP surface

With both BE instances running and homes seeded:

1. Acquire a real Auth0 access token via Bruno (see
   `../artemis_home_fe/temp/bruno.md`) or by capturing one from a
   browser DevTools network panel after login.
2. Hit each instance to verify the full session-exchange + ping loop:

   ```bash
   # Exchange Auth0 token → session JWT (against alpha)
   curl -sS -X POST http://localhost:6565/api/sessions \
     -H "Authorization: Bearer $AUTH0_ACCESS_TOKEN" | jq

   # Ping with the returned session JWT
   curl -sS http://localhost:6565/api/me/ping \
     -H "Authorization: Bearer $SESSION_JWT" | jq
   ```

3. Repeat against `:6566` (beta). Both should return their respective
   `home_id` and the same `user_sub`.

## Tests and quality gates

Run the full umbrella suite plus lint, format, coverage, and static
analysis:

```bash
mix all_tests
```

This runs `compile --warnings-as-errors`, `credo --strict`,
`format --check-formatted`, `coveralls --umbrella --raise` (enforced
100% on owned code via per-app `coveralls.json`), and
`dialyzer --list-unused-filters`.

A lighter pre-commit alias is available:

```bash
mix precommit       # compile, format check, test only
```

## Deploying as a container

The repo ships a `docker-compose.yml` template for Synology Container
Manager, Docker Desktop, or any Compose-aware host. Required env vars
use the `${VAR:?message}` pattern so Compose itself errors at
evaluation time if any are unset.

```bash
cp .env.example .env
$EDITOR .env                # fill in real values
docker compose up -d
```

A single host path (default `./keys`) is bind-mounted into the
container at `/app/apps/core/priv/keys` so the BE's RSA session
signing key survives container restarts. Per-instance container
deploys must use different `KEYS_PATH` values so alpha and beta
keep independent keypairs.

The multi-stage release `Dockerfile` is deferred to a later v0
commit or to v1. v0 itself runs locally via `mix phx.server`; the
deployment artifacts are forward-compatibility templates.

## Where to look next

- `planning/v0_docs/implementation-plan.md` — cross-repo architecture
  and decisions for the v0 PoC.
- `planning/v0_docs/step-by-step-commit-strat-be.md` — commit-by-commit
  build history of this repo.
- `../artemis_home_fe/planning/v0_docs/implementation-plan.md` —
  React SPA companion.
- `../artemis_home_fe/planning/issues.md` — known v0 issues being
  accepted (multi-home token exposure, per-home CORS config).
- `../artemis_home_fe/planning/v1-concerns.md` — items deferred to
  v1+ (register-home UI, logout UX, mobile clients, etc.).

