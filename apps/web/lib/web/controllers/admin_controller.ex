defmodule Web.AdminController do
  @moduledoc """
  Admin actions performed on behalf of the authenticated user against
  the Auth0 Management API.

  v0 exposes a single action: upserting a `{home_id, url}` entry on
  this user's `app_metadata.homes` list. The action requires an
  authenticated session — only the user themselves can edit their own
  homes registry in v0. Real role/scope enforcement (admin-only,
  audit logging) is v1+.

  Request:

      POST /api/admin/register-home
      Authorization: Bearer <session_jwt>
      Content-Type: application/json

      {"home_id": "alpha", "url": "http://localhost:6565"}

  Responses:

      200 OK
      {"home_id": "alpha", "url": "http://localhost:6565"}

      400 Bad Request                 -- missing/invalid home_id or url
      503 Service Unavailable         -- Auth0 Management API error
  """

  use Web, :controller

  @spec register_home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def register_home(conn, params) do
    %{user_sub: user_sub} = conn.assigns.current_user

    with {:ok, home_id} <- fetch_string(params, "home_id"),
         {:ok, url} <- fetch_string(params, "url"),
         {:ok, _} <- Core.Auth.register_home_for_user(user_sub, home_id, url) do
      json(conn, %{home_id: home_id, url: url})
    else
      {:error, {:missing_param, name}} ->
        render_status(conn, :bad_request, "missing_#{name}")

      {:error, _reason} ->
        render_status(conn, :service_unavailable, "auth0_unreachable")
    end
  end

  defp fetch_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_param, key}}
    end
  end

  defp render_status(conn, status, error_code) do
    conn
    |> put_status(status)
    |> json(%{error: error_code})
  end
end
