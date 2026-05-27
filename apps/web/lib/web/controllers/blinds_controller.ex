defmodule Web.BlindsController do
  @moduledoc """
  HTTP surface for the smart-blinds feature.

  All routes live under `/api/blinds` and are gated by the
  `:authenticated` pipeline so the bearer is a BE-issued session
  JWT. Write actions add `Web.Plugs.RequireRole` with
  `allowed: ~w(admin resident)` — guests can read state but not
  trigger HA service calls.

  ## Routes

      GET  /api/blinds                  -> index/2
      GET  /api/blinds/states           -> states/2
      POST /api/blinds/:id/position     -> set_position/2  (body: {"position": 0..100})
      POST /api/blinds/:id/open         -> open/2
      POST /api/blinds/:id/close        -> close/2
      POST /api/blinds/:id/stop         -> stop/2

  ## Response shapes

      GET /api/blinds
      [
        {"id": 1, "name": "Left Window",
         "ha_entity_id": "cover.living_room_tv_left_outbound_bottom",
         "manufacturer": "SmartWings", "protocol": "zwave",
         "sort_order": 0}
      ]

      GET /api/blinds/states
      [
        {"id": 1,
         "ha_entity_id": "cover.living_room_tv_left_outbound_bottom",
         "state": "open", "position": 65, "available": true}
      ]

  Blinds in the DB without a corresponding cache entry yet are still
  returned by `states/2` with `state: null, position: null,
  available: false`.

  ## Error responses

      400 {"error": "invalid_position"}
      404 {"error": "bad_id"}
      404 {"error": "not_found"}
      503 {"error": "ha_unreachable"}
      503 {"error": "ha_status"}        -- non-2xx from HA
  """

  use Web, :controller

  alias Core.Blinds
  alias Core.Blinds.StateCache

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    blinds = Blinds.list_blinds() |> Enum.map(&blind_summary/1)
    json(conn, blinds)
  end

  @spec states(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def states(conn, _params) do
    cache = StateCache.get_all()

    rows =
      Blinds.list_blinds()
      |> Enum.map(fn blind ->
        cache_entry = Map.get(cache, blind.ha_entity_id, %{})

        %{
          id: blind.id,
          ha_entity_id: blind.ha_entity_id,
          state: Map.get(cache_entry, :state),
          position: Map.get(cache_entry, :position),
          available: Map.get(cache_entry, :available, false)
        }
      end)

    json(conn, rows)
  end

  @spec set_position(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_position(conn, %{"id" => id_str} = params) do
    with {:ok, id} <- parse_id(id_str),
         {:ok, position} <- fetch_position(params),
         :ok <- Blinds.set_position(id, position) do
      send_resp(conn, :no_content, "")
    else
      error -> render_error(conn, error)
    end
  end

  @spec open(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def open(conn, %{"id" => id_str}), do: simple_action(conn, id_str, &Blinds.open/1)

  @spec close(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def close(conn, %{"id" => id_str}), do: simple_action(conn, id_str, &Blinds.close/1)

  @spec stop(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stop(conn, %{"id" => id_str}), do: simple_action(conn, id_str, &Blinds.stop/1)

  defp simple_action(conn, id_str, fun) do
    with {:ok, id} <- parse_id(id_str),
         :ok <- fun.(id) do
      send_resp(conn, :no_content, "")
    else
      error -> render_error(conn, error)
    end
  end

  defp blind_summary(blind) do
    %{
      id: blind.id,
      name: blind.name,
      ha_entity_id: blind.ha_entity_id,
      manufacturer: blind.manufacturer,
      protocol: blind.protocol,
      sort_order: blind.sort_order
    }
  end

  # Phoenix routes always bind `:id` as a binary, so a single
  # binary-guarded clause covers every reachable call site.
  defp parse_id(id_str) when is_binary(id_str) do
    case Integer.parse(id_str) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :bad_id}
    end
  end

  defp fetch_position(%{"position" => position}) when is_integer(position),
    do: {:ok, position}

  defp fetch_position(_), do: {:error, :invalid_position}

  defp render_error(conn, {:error, :bad_id}),
    do: render_status(conn, :not_found, "bad_id")

  defp render_error(conn, {:error, :not_found}),
    do: render_status(conn, :not_found, "not_found")

  defp render_error(conn, {:error, :invalid_position}),
    do: render_status(conn, :bad_request, "invalid_position")

  defp render_error(conn, {:error, :ha_unreachable}),
    do: render_status(conn, :service_unavailable, "ha_unreachable")

  defp render_error(conn, {:error, {:ha_status, _, _}}),
    do: render_status(conn, :service_unavailable, "ha_status")

  defp render_status(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: code})
  end
end
