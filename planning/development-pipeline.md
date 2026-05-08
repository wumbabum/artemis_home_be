# Development Pipeline

## Commit Strategy: Inside-Out, Atomic

Every commit should be a self-contained, buildable unit. Work from the innermost dependency outward.

### Order of Operations

1. **Schema + Migration** — Define the Ecto schema and its migration. Commit includes the schema module, migration file, and unit tests for changesets.
2. **Context** — Build the context module that uses the schema. Commit includes context functions and their tests. No controller, no web layer.
3. **Controller / Endpoint** — Wire the context into the web layer. Commit includes the controller, route, JSON view, and integration tests.
4. **Frontend** — Build the LiveView that consumes the API. Commit includes the LiveView module, templates, and any JS hooks.

### Example: Adding the `rooms` feature

```
Commit 1: Add Room schema and migration
  - priv/repo/migrations/..._create_rooms.exs
  - lib/core/home/room.ex
  - test/core/home/room_test.exs

Commit 2: Add Home context with rooms CRUD
  - lib/core/home/home.ex (create_room, list_rooms, get_room, update_room, delete_room)
  - test/core/home/home_test.exs

Commit 3: Add RoomController and routes
  - lib/web/controllers/room_controller.ex
  - lib/web/views/room_json.ex
  - lib/web/router.ex (add room routes)
  - test/web/controllers/room_controller_test.exs

Commit 4: (FE repo) Add rooms settings page
  - lib/artemis_home_fe_web/live/settings/rooms_live.ex
  - test/artemis_home_fe_web/live/settings/rooms_live_test.exs
```

### Commit Message Format

```
<scope>: <short description>

<optional body explaining why, not what>

Co-Authored-By: Oz <oz-agent@warp.dev>
```

Scopes: `core`, `dispatch`, `mcp`, `web`, `fe`, `infra`, `docs`, `test`

Examples:
- `core: add Room schema and migration`
- `core: add Home context with rooms CRUD`
- `web: add RoomController and routes`
- `fe: add rooms settings page`
- `infra: add tailscale container to docker-compose`

### Rules

- Never commit code that doesn't compile (`mix compile --warnings-as-errors`)
- Never commit a schema without changeset tests
- Never commit a context without context tests
- Never commit a controller without integration tests
- Every commit should pass `mix test` for the affected app
- No "WIP" commits on main — use feature branches if needed

## Quality Gates

### Before Every Commit

Run from the umbrella root (BE) or project root (FE):

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

### Before Every PR / Merge to Main

Run the full precommit suite:

```bash
mix precommit
```

This alias should be defined in `mix.exs` and should run:
1. `compile --warnings-as-errors`
2. `deps.unlock --unused`
3. `format --check-formatted`
4. `test`
5. `credo` (once added)

### Validation Checklist

For each feature, verify:

- [ ] Schema has `@type t()` defined
- [ ] All public functions have `@spec`
- [ ] All public functions have `@doc` (brief, relies on spec for details)
- [ ] Context functions return `{:ok, result}` / `{:error, reason}` tuples
- [ ] Controller tests cover happy path + at least one error case
- [ ] No hardcoded values — config comes from env vars or application config
- [ ] No `IO.inspect` or debug logging left in code
- [ ] JSON responses use consistent key naming (snake_case)

## Branch Strategy

- `main` — always deployable, always passes all tests
- `feature/<name>` — feature branches for multi-commit work
- PRs require passing CI before merge (once CI is set up)
- Squash merge to main to keep history clean

## Coding Standards

*To be defined by the developer.* This section will be populated with project-specific Elixir style rules, naming conventions, and patterns.

Placeholder for future topics:
- Module organization within each umbrella app
- Error handling patterns (when to use `with`, when to raise)
- Naming conventions for contexts, schemas, controllers
- Test organization and naming
- Configuration patterns (compile-time vs runtime)
- Logging standards
