# v0 BE Step-by-Step Commit Strategy

Execution sequencing for `artemis_home_be`. Architectural and technical choices live in `implementation-plan.md`. The FE sequence lives in `../../../artemis_home_fe/planning/v0_docs/step-by-step-commit-strat-fe.md` and depends on this work being completed and the BE end-to-end validated.

## Principles

- **Atomic**: each commit is a self-contained, buildable unit. Reverting one commit doesn't break earlier ones.
- **Inside-out**: external wrappers before the code that uses them, internal context modules before the web layer, the web layer before scripts and docs.
- **Quality gate per commit**: every commit must pass `mix all_tests` from the umbrella root before the next commit begins. This alias is introduced in B2. Before B2, the equivalent inline form is `mix compile --warnings-as-errors && mix format --check-formatted && mix test`. A failing gate must be fixed in the same commit (amend) before moving on.
- **Layer-boundary mocking**: when a commit introduces a module that depends on another module, the test mocks that dependency via Mox. The mock interface (a behaviour) is defined alongside the dependency.
- **Variety of test types**: ExUnit for examples, StreamData for property-based exercises of any function with variable-shape input, Mox for boundary mocking. Coverage tracked by ExCoveralls; lint enforced by Credo; static analysis by Dialyzer.
- **One conceptual change per commit**: deps go in their own commit; scaffolding is one commit; each module is its own commit.
- **Commit message format**: `<scope>: <short description>` with a `Co-Authored-By: Oz <oz-agent@warp.dev>` trailer, per `planning/development-pipeline.md`. Scopes used here: `infra`, `core`, `web`, `docs`.

## The `mix all_tests` Alias (BE umbrella)

Modeled on Citybase's `user_management_service` convention. Defined in B2:

```elixir
all_tests: [
  "compile --force --warnings-as-errors",
  "credo --strict",
  "format --check-formatted",
  "coveralls --umbrella --raise",
  "dialyzer --list-unused-filters"
]
```

Coverage is enforced at **100%** via per-app `coveralls.json` files. Each app's `coveralls.json` lists `skip_files` for phx-generated boilerplate (`Application`, `Endpoint`, `Router`, `Telemetry`, `Gettext`) and the HTTP boundary (`JwksCache.HttpFetcher`, exercised in smoke tests only). `--raise` makes `coveralls` fail the suite when coverage drops below 100% on our own code.

`test_coverage: [tool: ExCoveralls, threshold: 0]` in each `mix.exs` silences Mix's built-in 90% cover check; ExCoveralls is the sole authority.

`cli/0` declares `preferred_envs` so each tool runs under `Mix.env() == :test`:

```elixir
def cli do
  [
    preferred_envs: [
      all_tests: :test,
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.html": :test,
      dialyzer: :test,
      credo: :test
    ]
  ]
end
```

Dialyzer's PLT will be slow on first run (several minutes); subsequent runs are fast and incremental.

## Test Dependencies (added in B2)

- `mox ~> 1.1` — boundary mocking, `only: :test`
- `stream_data ~> 1.0` — property-based testing, `only: [:dev, :test]`
- `assertions ~> 0.16` — richer ExUnit assertion helpers, `only: :test`
- `excoveralls ~> 0.18` — coverage, `only: :test`
- `credo ~> 1.7` — lint, `only: [:dev, :test], runtime: false`
- `dialyxir ~> 1.4` — Dialyzer wrapper, `only: [:dev, :test], runtime: false`

`ex_machina` is intentionally omitted in v0 since there is no Ecto. Add in v1 alongside schemas.

## Branch and Remote Workflow

1. Commit the current uncommitted `v0_docs/` to `main` as `docs: add v0 implementation plan and commit strategy`.
2. User creates an empty remote repo named `artemis_home_be`.
3. Add remote, push `main`.
4. Branch off `v0-poc` from `main`. All v0 code work happens here.
5. After all v0 commits, push `v0-poc`, open a PR against `main`, merge without squash after review.

## Pre-Work Checklist (before any commits)

- Confirm latest stable Elixir/Erlang/Phoenix versions installed via `asdf` or equivalent.
- Confirm the empty remote `artemis_home_be` exists on GitHub.
- Confirm Auth0 tenant access. The Application, API, M2M app, and Post-Login Action can be configured after B4 lands and before B8's pause point.

## Commit Sequence

Numbering: `B<n>`. Pause points are interspersed and explicit.

### B1 — `infra: scaffold umbrella with core, dispatch, mcp, web child apps`

What:
- `mix new artemis_home_be --umbrella` (run such that the existing repo files are preserved; staging the generator output and merging into the existing directory is acceptable).
- From the umbrella root: `mix new apps/core --sup`, `mix new apps/dispatch --sup`, `mix new apps/mcp --sup`, `mix phx.new.web apps/web --adapter cowboy --no-ecto --no-mailer --no-html --no-assets --no-dashboard --no-live`.
- Manually add `{Phoenix.PubSub, name: Web.PubSub}` to `apps/web/lib/web/application.ex` (works around the `--no-ecto` PubSub gap noted in the umbrella rule).
- Add `.tool-versions` at the umbrella root pinning Elixir 1.19 and the matching Erlang/OTP.
- Add a root `.gitignore` (cover `_build`, `deps`, `*.beam`, `priv/keys/`, env files).
- Add `apps/core/priv/keys/.gitkeep` so the directory exists, with `*.pem` ignored.

Validation: `mix compile --warnings-as-errors && mix format --check-formatted && mix test` passes from the umbrella root. The `all_tests` alias doesn't exist yet.

### B2 — `infra: add deps, all_tests alias, and runtime config skeleton`

What:
- `apps/core/mix.exs`:
  - Runtime deps: `{:req, "~> 0.5"}`, `{:joken, "~> 2.6"}`, `{:jason, "~> 1.4"}`.
  - Test deps: `{:mox, "~> 1.1", only: :test}`, `{:stream_data, "~> 1.0", only: [:dev, :test]}`, `{:assertions, "~> 0.16", only: :test}`, `{:excoveralls, "~> 0.18", only: :test}`.
  - `elixirc_paths(:test)` includes `"test/support"` so shared test helpers can live there.
  - `test_coverage: [tool: ExCoveralls, threshold: 0]` (each child app needs this).
- Root `mix.exs`:
  - Deps: `{:excoveralls, "~> 0.18", only: :test}`, `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}`, `{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}`.
  - `project/0`: `test_coverage: [tool: ExCoveralls, threshold: 0]`, `dialyzer: [plt_add_apps: [:ex_unit, :mix], ignore_warnings: ".dialyzer_ignore.exs"]`.
  - `cli/0` with `preferred_envs` for `all_tests`, `coveralls`, `"coveralls.detail"`, `"coveralls.html"`, `dialyzer`, `credo` — all `:test`.
  - Aliases: `all_tests` (full suite, see top of file) and a lighter `precommit: ["compile --warnings-as-errors", "format --check-formatted", "test"]` for tighter inner-loop runs.
- Add empty `.dialyzer_ignore.exs` (`[]`) at the umbrella root.
- Per-app `coveralls.json` files with `minimum_coverage: 100` and `skip_files` for phx-generated boilerplate and the HTTP boundary. The umbrella-root `coveralls.json` alone is not honored by per-app `coveralls --umbrella` runs.
- `config/runtime.exs`: `case config_env() do` — `:test` no-op (test.exs supplies values), `:dev` uses `System.get_env(name, default)`, `:prod` uses `System.fetch_env!(name)` so container boot fails fast on missing required vars. See implementation-plan.md for the full env var list.
- `config/prod.exs`: static prod endpoint settings only (force_ssl, IP binding). Env-driven values stay in runtime.exs.
- `mix deps.get`, `mix deps.unlock --unused`.

Validation: `mix all_tests` passes from the umbrella root. First Dialyzer run will build the PLT (a few minutes); commit the resulting `.dialyzer_ignore.exs` if any warnings need silencing — for v0 it holds a single regex skipping the Phoenix 1.8 + OTP 28 `pattern_match` false positive in `Phoenix.Router`.

### B3 — `core: add Auth0 JWKS cache`

What:
- `apps/core/lib/core/auth/jwks_cache.ex`: define `Core.Auth.JwksCache` behaviour with `@callback fetch(kid :: String.t()) :: {:ok, map()} | {:error, term()}` and a GenServer impl that calls `https://#{domain}/.well-known/jwks.json` via Req. ETS or `:persistent_term` map keyed by `kid` is fine.
- Add the GenServer to `apps/core/lib/core/application.ex` supervision tree.
- `apps/core/test/core/auth/jwks_cache_test.exs`: one ExUnit happy-path test plus one StreamData property test asserting any well-formed JWKS response with N keys produces N cacheable entries. Req is stubbed via Mox.

Validation: `mix all_tests` passes from the umbrella root.

### B4 — `core: add Auth0 access token verifier`

What:
- `apps/core/lib/core/auth/auth0_verifier.ex`: Joken-based verifier. Validates `iss == "https://#{domain}/"`, `aud == config audience`, `exp`, RS256 signature against `JwksCache.fetch/1` for the token's `kid`. Asserts `Map.get(claims, "https://artemis.app/homes")` contains a `home_id` matching `Application.get_env(:core, :home_id)`.
- Define a `Core.Auth.Auth0Verifier` behaviour with `@callback verify(token :: String.t()) :: {:ok, claims} | {:error, reason}` so higher layers can Mox it.
- Test: happy-path ExUnit test using Mox to stub `JwksCache`. Tokens are generated by a `test/support/auth0_token_helper.ex` that signs with a fixture RSA key whose public half is returned by the mocked cache.

Validation: `mix all_tests` passes from the umbrella root.

### B5 — `core: add session signing key loader`

What:
- `apps/core/lib/core/auth/session_signing_key.ex`: `load!/0` reads `apps/core/priv/keys/session_signing.pem` and `.pub.pem`; if absent, generates an RSA-2048 keypair, writes both files with mode 0600, and returns the loaded `%JOSE.JWK{}` (or Joken signer).
- Test: ExUnit test in a temp dir; asserts file mode and contents round-trip. StreamData property: any number of repeated calls produces the same key bytes.

Validation: `mix all_tests` passes from the umbrella root.

### B6 — `core: add session token issuer and verifier`

What:
- `apps/core/lib/core/auth/session_token.ex`: `issue(claims_map)` and `verify(token)`. RS256 using the keypair from `SessionSigningKey`. TTL 1 hour. Required claims: `sub`, `home_id`, `iat`, `exp`.
- Define a `Core.Auth.SessionToken` behaviour for Mox-ability.
- Tests:
  - ExUnit round-trip happy-path.
  - StreamData property: any well-formed claims map round-trips through `issue/verify` unchanged.
  - One expired-token assertion (the error path differs structurally from "signature invalid").

Validation: `mix all_tests` passes from the umbrella root.

### B7 — `core: add Auth0 Management API client wrapper`

What:
- `apps/core/lib/core/auth/management_api.ex`: `update_app_metadata(user_sub, patch_map) :: {:ok, _} | {:error, reason}`. Acquires the M2M token via `POST /oauth/token` (client credentials grant), caches it in `:persistent_term` for ~85% of its lifetime, then performs `PATCH /api/v2/users/:user_sub`.
- Define a `Core.Auth.ManagementApi` behaviour.
- Test: ExUnit happy-path stubbing Req via Mox. One assertion that token caching avoids a second token fetch when called twice within the cache window.

Validation: `mix all_tests` passes from the umbrella root.

### B8 — `core: add Auth context API`

What:
- `apps/core/lib/core/auth.ex`: the public API. Uses application config to pick concrete or Mox impls of `JwksCache`, `Auth0Verifier`, `SessionToken`, `ManagementApi`.
  - `exchange_auth0_token(token, home_id)` — verifies the Auth0 token, builds claims `%{sub, home_id, iat, exp}`, calls `SessionToken.issue/1`, returns `{:ok, %{user_sub, home_id, session_jwt}}`.
  - `verify_session(token)` — delegates to `SessionToken.verify/1`.
  - `register_home_for_user(user_sub, home_id, url)` — calls `ManagementApi.update_app_metadata/2` with the new homes list.
- Test: one happy-path ExUnit test per function with all four internal modules Mox-ed.

Validation: `mix all_tests` passes from the umbrella root.

### Pause Point B-α — smoke test against real Auth0

Before writing the web layer, halt and:

1. Verify Auth0 is fully configured: single SPA Application driving both Bruno (testing-only) and the React FE, plus the API resource, M2M Application, and Post-Login Action.
2. Capture a real Auth0 access token via Bruno (per `../../../artemis_home_fe/temp/bruno.md`) or from a browser DevTools network panel after a login.
3. From the BE umbrella root: `HOME_ID=alpha mix run -e 'Core.Auth.exchange_auth0_token("...", "alpha") |> IO.inspect()'`.
4. Confirm `{:ok, %{user_sub: ..., home_id: "alpha", session_jwt: "..."}}`.

If anything fails, fix in place. Do not move to the web layer until the smoke test passes.

### B9 — `web: add RequireSession plug`

What:
- `apps/web/lib/web/plugs/require_session.ex`: extracts `Authorization: Bearer <token>`, calls `Core.Auth.verify_session/1`, on success assigns `:current_user` to `%{user_sub, home_id}`. On failure halts with 401 JSON.
- Test: conn-based ExUnit test with `Core.Auth` Mox-ed.

Validation: `mix all_tests` passes from the umbrella root.

### B9.5 — `web: add CORSPlug allowing FE origin`

What:
- Add `{:cors_plug, "~> 3.0"}` to `apps/web/mix.exs`.
- `apps/web/lib/web/endpoint.ex`: insert `plug CORSPlug, origin: cors_origins()` ahead of the router so preflight (`OPTIONS`) requests are answered before the router runs. Define `cors_origins/0` to read from `Application.fetch_env!(:web, :cors_allowed_origins)`.
- `config/runtime.exs`: read `CORS_ALLOWED_ORIGINS` (comma-separated). `:dev` defaults to `"http://localhost:6587"`. `:prod` uses `System.fetch_env!/1` and parses on commas — must be set explicitly.
- `config/test.exs`: set `config :web, cors_allowed_origins: ["http://localhost:6587"]` so the test env doesn't need the env var.
- Test: conn-based ExUnit test that an `OPTIONS /api/sessions` request from `http://localhost:6587` returns 204 with the appropriate `access-control-allow-*` headers, and a request from `http://evil.example.com` does not.

Why here: B10 introduces the first `POST /api/sessions` route that the React FE will hit cross-origin. CORS must be in place before that endpoint lands, otherwise the FE preflight will fail and obscure the bug as a routing problem.

Validation: `mix all_tests` passes from the umbrella root.

### B10 — `web: add POST /api/sessions endpoint`

What:
- `apps/web/lib/web/controllers/session_controller.ex` with `create/2`.
- `apps/web/lib/web/router.ex`: pipeline `:api` (`accepts: [:json]`); route `post "/api/sessions", SessionController, :create`.
- Controller test with `Core.Auth.exchange_auth0_token/2` Mox-ed.

Validation: `mix all_tests` passes from the umbrella root.

### B11 — `web: add GET /api/me/ping endpoint`

What:
- `apps/web/lib/web/controllers/me_controller.ex` with `ping/2`.
- `apps/web/lib/web/router.ex`: pipeline `:authenticated` (chains `:api` + `RequireSession`); route `get "/api/me/ping", MeController, :ping`.
- Controller test asserting a valid session yields a 200 response with `%{home_id, user_sub, role: "admin"}`.

Validation: `mix all_tests` passes from the umbrella root.

### B12 — `web: add POST /api/admin/register-home endpoint`

What:
- `apps/web/lib/web/controllers/admin_controller.ex` with `register_home/2`. Calls `Core.Auth.register_home_for_user/3`.
- Route under `:authenticated`.
- Controller test with `Core.Auth.register_home_for_user/3` Mox-ed.

Validation: `mix all_tests` passes from the umbrella root.

### B13 — `infra: add mix seed.homes task`

What:
- `apps/core/lib/mix/tasks/seed_homes.ex`: defines `Mix.Tasks.SeedHomes`. Accepts `--user-sub`, repeated `--home <id>:<url>`. Calls `Core.Auth.register_home_for_user/3` once per home.
- Root `mix.exs` aliases: add `"seed.homes": "seed_homes"`.
- No automated test (mix task is a thin wrapper; tested manually at the next pause point).

Validation: `mix all_tests` passes from the umbrella root. `mix help seed.homes` resolves the alias.

### Pause Point B-β — seed against real Auth0

Halt and:

1. Confirm M2M credentials are exported in the user's shell.
2. Run `mix seed.homes --user-sub "auth0|..." --home alpha:http://localhost:6565 --home beta:http://localhost:6566`.
3. Verify in the Auth0 dashboard that the test user's `app_metadata.homes` contains both entries.

### B-deploy — `infra: add docker-compose template and .env.example for deployment`

What:
- `docker-compose.yml` at the umbrella root. Required env vars use `${VAR:?message}` so Docker Compose itself errors at evaluation time if any are unset. Optional vars use `${VAR:-default}`. Single bind mount maps `${KEYS_PATH:-./keys}` to `/app/apps/core/priv/keys` so the BE's RSA session signing key survives container restarts.
- `.env.example` at the umbrella root documenting every variable the compose file references. Users copy to `.env` (gitignored) and fill in real values.
- `.gitignore` updated: ignore `/.env` and `/keys/`.

The `Dockerfile` (multi-stage release build, push to Docker Hub) is deferred to a later v0 commit or to v1. v0 itself runs locally with `mix phx.server`; the deployment artifacts are forward-compatibility templates.

Validation: `mix all_tests` passes (no code changes here). `docker compose config` would validate the compose file against a populated `.env`.

### B14 — `docs: add README with v0 runbook`

What:
- `README.md` at the umbrella root: prereqs, environment variables (link to `.env.example` and the implementation-plan env table), how to run alpha and beta in parallel locally, how to seed homes, how to run `mix all_tests`, brief notes on deploying as a Docker container, links to `planning/v0_docs/implementation-plan.md`, `planning/v0_docs/step-by-step-commit-strat-be.md`, and `../artemis_home_fe/planning/v0_docs/step-by-step-commit-strat-fe.md`.

Validation: `mix all_tests` passes from the umbrella root.

### Pause Point B-γ — full BE end-to-end

Before opening a PR / moving to the FE:

1. Start alpha: `HOME_ID=alpha PORT=6565 mix phx.server`.
2. Start beta in a second terminal: `HOME_ID=beta PORT=6566 mix phx.server`.
3. Using a real Auth0 token captured in a browser, hit `POST localhost:6565/api/sessions` then `GET localhost:6565/api/me/ping` with the returned session JWT. Repeat against `:6566`.
4. Confirm both return the expected `home_id` and `user_sub`.
5. From a separate origin (e.g. a Vite dev server on `http://localhost:6587` or a `curl` with `-H 'Origin: http://localhost:6587'`), send an `OPTIONS /api/sessions` preflight and confirm the BE responds with the configured CORS headers (B9.5).

Push `v0-poc`, open PR, request review and merge (no squash). After merge, proceed to the FE sequence at `../../../artemis_home_fe/planning/v0_docs/step-by-step-commit-strat-fe.md`. The BE-side FE plan that used to live here was deleted when the FE pivot landed; the FE repo now owns its own planning tree.

## Pause Points Summary (BE)

- **B-α** (after B8): real Auth0 token round-trip through `Core.Auth.exchange_auth0_token/2`.
- **B-β** (after B13): `mix seed.homes` against the real Auth0 tenant.
- **B-γ** (after B14): full BE end-to-end with curl or HTTPie before starting the FE sequence.

At each pause point I will stop and explicitly confirm before continuing. If a pause point reveals a problem, fixes are made in subsequent commits with appropriate scope, not by rewriting prior commits.

## What Could Cause an Unscheduled Pause

I will also pause out of cycle if:

- An assumption in the implementation plan turns out to be wrong.
- A library API has changed in a way that requires deviation from the plan.
- The `phx.new.web` or `mix new` generator emits something different from what the plan predicts (e.g. a different supervision tree shape).
- A test requires unexpected fixtures or scaffolding that should be discussed first.
- `mix all_tests` fails for a reason that isn't covered by the in-progress commit (e.g. a Dialyzer warning surfaced by a library upgrade).

In all such cases, I will surface the conflict, propose options, and wait for direction.
