# HA WebSocket Client in Elixir — Research

## Libraries Evaluated

### 1. Fresh (Recommended)
**Version:** 0.4.4 | **Stars:** 62 | **Built on:** Mint + MintWebSocket

Simple, resilient WebSocket client with auto-reconnect. Callback-based like GenServer.

```elixir
defmodule Core.HAWebSocket do
  use Fresh

  def handle_connect(_status, _headers, state) do
    # Send auth message
    {:reply, {:text, Jason.encode!(%{type: "auth", access_token: state.token})}, state}
  end

  def handle_in({:text, msg}, state) do
    case Jason.decode!(msg) do
      %{"type" => "auth_ok"} -> {:ok, %{state | authenticated: true}}
      %{"type" => "event", "event" => event} -> handle_ha_event(event, state)
      _ -> {:ok, state}
    end
  end
end
```

**Pros:** Minimal API, auto-reconnect with backoff, built on Mint (modern HTTP stack).
**Cons:** Smaller community (62 stars), last release Apr 2024.

### 2. WebSockex
**Version:** 0.5.1 | **Stars:** ~700 | **Mature, widely used**

OTP special process, fits into supervision trees. More features than Fresh.

```elixir
defmodule Core.HAWebSocket do
  use WebSockex

  def start_link(url, state) do
    WebSockex.start_link(url, __MODULE__, state)
  end

  def handle_frame({:text, msg}, state) do
    {:ok, state}
  end

  def handle_disconnect(_reason, state) do
    {:reconnect, state}
  end
end
```

**Pros:** Battle-tested, OTP-native, reconnect support, telemetry events.
**Cons:** Older codebase, doesn't use Mint (uses :gun or :hackney under the hood).

### 3. Mint.WebSocket (Low-level)
**Version:** 1.0.5 | **Downloads:** 1.6M+ | **Functional, process-less**

Raw WebSocket operations. You manage the connection lifecycle yourself.

**Pros:** Maximum control, functional API, HTTP/2 WebSocket support.
**Cons:** You build the GenServer yourself — significant boilerplate for persistent connections.

## Recommendation

**Use Fresh** for the HA WebSocket connection. It's the simplest option that handles reconnection automatically and is built on the modern Mint stack. The HA WebSocket connection needs:
- Persistent connection with auto-reconnect
- JSON message sending/receiving
- Event handling for pairing events
- Supervised process

Fresh covers all of these with minimal code. If Fresh proves too immature, WebSockex is the fallback.

## HA WebSocket Specifics

Tested connection format:
```
ws://<HA_HOST>:8123/api/websocket

# Auth handshake:
→ Server sends: {"type": "auth_required", "ha_version": "..."}
→ Client sends: {"type": "auth", "access_token": "<HA_TOKEN>"}
→ Server sends: {"type": "auth_ok", "ha_version": "..."}

# Then: command phase with incrementing message IDs
→ Client sends: {"id": 1, "type": "zwave_js/add_node", ...}
← Server sends: {"id": 1, "type": "result", "success": true, ...}
← Server sends: {"id": 1, "type": "event", "event": {...}}
```
