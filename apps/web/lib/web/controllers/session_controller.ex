defmodule Web.SessionController do
  @moduledoc """
  Exchanges an Auth0-issued access token for a BE-issued session JWT
  scoped to this home.

  Request:

      POST /api/sessions
      Authorization: Bearer <auth0_access_token>

  Responses:

      200 OK
      {"user_sub": "...", "home_id": "...", "session_jwt": "..."}

      400 Bad Request                 -- missing/malformed Authorization header
      401 Unauthorized                -- Core.Auth.exchange_auth0_token/2 rejected
      403 Forbidden                   -- home_not_authorized (token valid but
                                         this BE's HOME_ID is not in the
                                         user's homes list)
      503 Service Unavailable         -- upstream Auth0 transport error
  """

  use Web, :controller

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    with {:ok, token} <- extract_bearer(conn),
         {:ok, home_id} <- fetch_home_id() do
      case Core.Auth.exchange_auth0_token(token, home_id) do
        {:ok, result} ->
          conn
          |> put_status(:ok)
          |> json(result)

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      {:error, :bad_request} ->
        render_status(conn, :bad_request, "missing_bearer")

      {:error, :missing_home_id_config} ->
        render_status(conn, :service_unavailable, "misconfigured")
    end
  end

  defp extract_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :bad_request}
    end
  end

  defp fetch_home_id do
    case Application.get_env(:core, :home_id) do
      home_id when is_binary(home_id) and home_id != "" -> {:ok, home_id}
      _ -> {:error, :missing_home_id_config}
    end
  end

  # Authorized-but-wrong-home: this BE is not in the user's home registry.
  defp render_error(conn, :home_not_authorized),
    do: render_status(conn, :forbidden, "home_not_authorized")

  # Auth0 issuer/audience/expiry/signature/missing-config errors collapse to 401.
  defp render_error(conn, reason)
       when reason in [
              :invalid_token,
              :invalid_iss,
              :missing_iss,
              :invalid_aud,
              :missing_aud,
              :missing_aud_config,
              :token_expired,
              :missing_exp,
              :missing_kid,
              :unknown_kid,
              :missing_sub_claim
            ],
       do: render_status(conn, :unauthorized, Atom.to_string(reason))

  # Upstream Auth0 transport errors (network, JWKS fetch, malformed response).
  defp render_error(conn, _other),
    do: render_status(conn, :service_unavailable, "auth0_unreachable")

  defp render_status(conn, status, error_code) do
    conn
    |> put_status(status)
    |> json(%{error: error_code})
  end
end
