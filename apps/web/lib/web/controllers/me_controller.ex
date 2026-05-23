defmodule Web.MeController do
  @moduledoc """
  Identity probe for the authenticated user against this home BE.

  Request:

      GET /api/me/ping
      Authorization: Bearer <session_jwt>

  The route is gated by the `:authenticated` pipeline so the bearer is a
  BE-issued session JWT (not an Auth0 access token). `RequireSession`
  has already assigned `:current_user` to `%{user_sub, home_id}` by the
  time `ping/2` runs.

  Response:

      200 OK
      {"user_sub": "...", "home_id": "...", "role": "admin"}

  `role` is hard-coded to `"admin"` in v0 — every authenticated user is
  treated as the owner of any home they hold a session for. v1+ adds
  real role/scope enforcement on the session JWT.
  """

  use Web, :controller

  @spec ping(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ping(conn, _params) do
    %{user_sub: user_sub, home_id: home_id} = conn.assigns.current_user

    json(conn, %{
      user_sub: user_sub,
      home_id: home_id,
      role: "admin"
    })
  end
end
