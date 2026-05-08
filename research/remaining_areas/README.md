# Remaining Research Areas — Summaries

## QR Code Scanning in LiveView

**Winner: html5-qrcode** (1M+ weekly npm downloads, Apache-2.0)
- Works via phx-hook with `phx-update="ignore"` on the container div
- Must call `scanner.clear()` in the hook's `destroyed()` callback to prevent event leaks
- Supports camera (back-facing by default on mobile) and file upload fallback
- Import via `npm install html5-qrcode` in assets, bundle with esbuild
- Z-Wave QR code strings are 52+ characters — html5-qrcode handles these natively
- iOS Safari requires HTTPS for camera access (Tailscale Funnel provides this)

See `qr_scanning/html5_qrcode/` for integration code example from a real LiveView issue (#2399).

## PWA in Phoenix LiveView

Straightforward — 3 steps:
1. Create `manifest.json` in `assets/static/` (or `priv/static/`)
2. Add to `static_paths` in `my_app_web.ex`: `~w(... manifest.json sw.js)`
3. Add `<link rel="manifest" href="/manifest.json" />` to `root.html.heex`

Service worker (`sw.js`): use Workbox for cache strategies. Cache-first for static assets, network-first for API calls.

Multiple reference implementations exist:
- `dwyl/PWA-Liveview` (30 stars) — full offline-first PWA with Yjs CRDTs
- `thisistonydang/liveview-svelte-pwa` (298 stars) — local-first with IndexedDB
- `mishka.tools` blog — Workbox integration guide for Phoenix

For Artemis v1: simple PWA (manifest + basic service worker for offline splash). No CRDT/offline-first needed.

## Cloak Ecto — Field Encryption

**Library:** `cloak_ecto` ~> 1.3 + `cloak` ~> 1.1

Setup:
1. Generate 256-bit key: `32 |> :crypto.strong_rand_bytes() |> Base.encode64()`
2. Create vault module (`Core.Vault`) with AES-GCM cipher
3. Add vault to supervision tree
4. Create encrypted type: `use Cloak.Ecto.Binary, vault: Core.Vault`
5. Use in schema: `field :ha_token, Core.Encrypted.Binary`
6. Migration: field type is `:binary`

Key from env var via `init/1` callback. Supports key rotation via `mix cloak.migrate.ecto`.

**For Artemis:** Use for `ha_token_enc` field on `homes` table. Store CLOAK_KEY in Docker env.

## Tailscale Funnel in Docker

**Confirmed working on Synology NAS.** Multiple guides with exact configs.

`serve.json` format (generic, reusable via `${TS_CERT_DOMAIN}`):
```json
{
  "TCP": {"443": {"HTTPS": true}},
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/": {"Proxy": "http://127.0.0.1:4001"}
      }
    }
  }
}
```

Docker compose pattern:
- Tailscale container as sidecar with `TS_SERVE_CONFIG`, `TS_STATE_DIR`, `TS_AUTHKEY`
- App container uses `network_mode: service:tailscale`
- Must persist `/var/lib/tailscale` in a volume
- `cap_add: net_admin, sys_module` + `/dev/net/tun` device
- Use OAuth client (never expires) over auth key (90 day max) for production

**For Artemis:** The FE container uses `network_mode: service:tailscale`. Tailscale Funnel proxies HTTPS port 443 to the FE's port 4001. The BE is not exposed publicly — only accessible from within the docker network.

## Oban Dynamic Scheduling

Pattern: GenServer evaluator + Oban workers.

```elixir
defmodule Dispatch.ScheduleEvaluator do
  use GenServer

  def handle_info(:evaluate, state) do
    now = DateTime.utc_now()
    due_schedules = Core.BlindSchedules.list_due(now)
    
    Enum.each(due_schedules, fn schedule ->
      %{schedule_id: schedule.id}
      |> Dispatch.Workers.BlindScheduleWorker.new()
      |> Oban.insert()
    end)

    Process.send_after(self(), :evaluate, :timer.seconds(60))
    {:noreply, state}
  end
end
```

For cron parsing: use `crontab` hex package (~> 1.1) to evaluate if a schedule is due.

## Email/SMS Delivery

**Email:** Swoosh (~> 1.16) with Req adapter or built-in adapters for SendGrid, Postmark, Mailgun, SES.
**SMS:** `ex_twilio` or direct Twilio REST API via Req.

Both deferred — provider selection happens later.
