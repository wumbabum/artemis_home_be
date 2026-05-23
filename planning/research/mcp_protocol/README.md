# MCP Server Protocol in Elixir — Research

## Existing Libraries (as of May 2026)

### 1. Hermes MCP (Recommended)
**Version:** 0.14.1 | **Full client + server** | **Streamable HTTP + stdio transports**

Most complete Elixir MCP implementation. Supports tools, resources, prompts. Server with DSL.

```elixir
defmodule Mcp.Server do
  use Hermes.Server,
    name: "Artemis Home",
    version: "1.0.0",
    capabilities: [:tools]

  def init(_client_info, frame) do
    {:ok, frame
      |> register_tool("list_blinds", description: "List all blinds in a home")
      |> register_tool("control_blind", 
        input_schema: %{
          blind_id: {:required, :integer},
          action: {:required, :string, enum: ["open", "close", "set_position"]},
          position: {:optional, :integer, min: 0, max: 100}
        },
        description: "Control a blind")}
  end

  def handle_tool("list_blinds", _params, frame) do
    blinds = Core.Blinds.list_blinds(frame.assigns.home_id)
    {:reply, Jason.encode!(blinds), frame}
  end

  def handle_tool("control_blind", params, frame) do
    result = Core.Blinds.command(params.blind_id, params.action, params[:position])
    {:reply, Jason.encode!(result), frame}
  end
end
```

**Pros:** Active development, Phoenix integration, streamable HTTP transport.
**Cons:** Relatively new (0.x version).

### 2. ExMCP
**Version:** 0.9.1 | **100% MCP conformance** | **Client + Server + ACP**

Most feature-complete. Includes Phoenix Plug integration, DSL, native BEAM transport.

### 3. ConduitMCP
**Version:** 0.9.2 | **Three build modes** | **DSL, Manual, Component**

Clean DSL, Phoenix-ready, rate limiting built in.

### 4. Custom JSON-RPC
Build it yourself with plain Phoenix controllers. MCP is just JSON-RPC 2.0.

## Recommendation

**Use Hermes MCP** for the `:mcp` umbrella app. It has the cleanest API, active development, and native Phoenix integration. The server can be mounted as a Plug in the `:web` app's router:

```elixir
forward "/mcp", to: Hermes.Server.Transport.StreamableHTTP.Plug, 
  init_opts: [server: Mcp.Server]
```

PAT authentication can be handled by a plug before the MCP endpoint.

## MCP Tool Definitions for Artemis

```
list_blinds(home_id) → [{id, name, state, position}]
control_blind(blind_id, action, position?) → {ok/error}
list_rooms(home_id) → [{id, name}]
list_blind_schedules(home_id) → [{id, name, active}]
toggle_blind_schedule(schedule_id) → {ok/error}
execute_saved_config(config_id) → {ok/error, per_device_results}
```
