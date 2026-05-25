defmodule Web.Plugs.RequireRole do
  @moduledoc """
  Authorizes a request by checking that
  `conn.assigns.current_user.role` is in the configured `:allowed`
  list.

  Halts with `403 {"error": "forbidden"}` when the role is missing
  or not in the allow-list. Assumes `Web.Plugs.RequireSession` has
  already run upstream — `:current_user` must be assigned.

  Used on the write-side blinds routes (`POST /api/blinds/...`) to
  keep `guest`-role users from triggering Home Assistant service
  calls.

  ## Usage

      pipeline :writable do
        plug Web.Plugs.RequireRole, allowed: ~w(admin resident)
      end

  Pass the allow-list as a list of role-name strings via `:allowed`.
  Required — missing `:allowed` raises at `init/1` so misconfigured
  pipelines fail at boot, not at request time.
  """

  import Plug.Conn
  alias Phoenix.Controller

  @spec init(keyword()) :: keyword()
  def init(opts) do
    case Keyword.fetch(opts, :allowed) do
      {:ok, roles} when is_list(roles) and roles != [] ->
        unless Enum.all?(roles, &is_binary/1) do
          raise ArgumentError,
                "Web.Plugs.RequireRole expects :allowed to be a non-empty list of " <>
                  "role-name strings, got: #{inspect(roles)}"
        end

        opts

      _ ->
        raise ArgumentError, "Web.Plugs.RequireRole requires an :allowed keyword option"
    end
  end

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    allowed = Keyword.fetch!(opts, :allowed)

    case conn.assigns[:current_user] do
      %{role: role} when is_binary(role) ->
        if role in allowed, do: conn, else: forbidden(conn)

      _ ->
        forbidden(conn)
    end
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> Controller.json(%{error: "forbidden"})
    |> halt()
  end
end
