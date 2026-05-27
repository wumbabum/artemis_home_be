defmodule Web.Plugs.RequireSession do
  @moduledoc """
  Extracts a session JWT from the `Authorization: Bearer <token>` header,
  validates it via `Core.Auth.verify_session/1`, and assigns the resolved
  identity to `conn.assigns.current_user` as `%{user_sub, home_id, role}`.

  Halts with `401 {"error": "unauthorized"}` for any of:

    * Missing or non-`Bearer` `Authorization` header
    * Token rejected by `Core.Auth.verify_session/1` (expired, bad
      signature, missing claims, etc.)
    * Verified claims that do not contain `sub`, `home_id`, and `role`
      (v0 session JWTs that pre-date the role claim are rejected and
      re-login is required)

  Routes that should be unauthenticated must omit this plug from their
  pipeline.
  """

  import Plug.Conn
  alias Phoenix.Controller

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with {:ok, token} <- extract_bearer(conn),
         {:ok, claims} <- Core.Auth.verify_session(token),
         {:ok, user} <- build_user(claims) do
      assign(conn, :current_user, user)
    else
      _ -> unauthorized(conn)
    end
  end

  defp extract_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp build_user(%{"sub" => sub, "home_id" => home_id, "role" => role})
       when is_binary(sub) and is_binary(home_id) and is_binary(role) do
    {:ok, %{user_sub: sub, home_id: home_id, role: role}}
  end

  defp build_user(_claims), do: :error

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Controller.json(%{error: "unauthorized"})
    |> halt()
  end
end
