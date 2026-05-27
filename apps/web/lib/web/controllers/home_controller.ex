defmodule Web.HomeController do
  @moduledoc """
  Home-level metadata + integration readiness for the FE.

  Returns the data the FE needs once at dashboard load to drive
  per-device-type UI affordances (e.g. enable the blinds button
  only when HA's Z-Wave integration is loaded).

  ## Route

      GET /api/home
      Authorization: Bearer <session_jwt>

  ## Response

      200 OK
      {
        "user_sub": "google-oauth2|abc",
        "home_id": "alpha",
        "role": "admin",
        "integrations": {
          "zwave": {
            "available": true,
            "state": "loaded",
            "reason": null,
            "title": "Z-Wave JS"
          }
        }
      }

  Always returns `200` for authenticated requests. HA being
  unreachable does not 5xx the endpoint — the FE still needs the
  home identity, user sub, and role even when integration status
  can't be read. HA-side problems are reflected in
  `integrations.<name>.available` and `.reason` instead.

  This endpoint subsumes the v0 `/api/me/ping` route, which has
  been removed. The FE should fetch `/api/home` once per
  authenticated session to get identity + capabilities in one
  round trip.

  ### `integrations.<name>` fields

    * `available` — boolean. The FE's green-light signal.
    * `state`     — HA's raw state string (`"loaded"`,
      `"setup_error"`, etc.) or `null` when no entry exists.
    * `reason`    — `null` when available; otherwise one of
      `"not_installed"`, `"disabled_in_ha"`, `"ha_unreachable"`,
      `"ha_status"`, or HA's verbatim `reason` / `state` string.
    * `title`     — HA's UI label for the integration, or `null`
      when no entry exists.

  Role-gating: routed through the existing `:authenticated`
  pipeline. Any session can read; the response is identical for
  admin / resident / guest. Roles still matter on the write-side
  blinds routes — this endpoint is purely informational.
  """

  use Web, :controller

  alias Core.Home

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    %{user_sub: user_sub, home_id: home_id, role: role} = conn.assigns.current_user

    json(conn, %{
      user_sub: user_sub,
      home_id: home_id,
      role: role,
      integrations: %{
        zwave: integration_payload("zwave_js")
      }
    })
  end

  defp integration_payload(domain) do
    case Home.integration_status(domain) do
      {:ok, status} ->
        Map.take(status, [:available, :state, :reason, :title])

      {:error, :ha_unreachable} ->
        unavailable("ha_unreachable")

      {:error, {:ha_status, _status, _body}} ->
        unavailable("ha_status")

      {:error, _other} ->
        unavailable("unknown")
    end
  end

  defp unavailable(reason) do
    %{available: false, state: nil, reason: reason, title: nil}
  end
end
