defmodule Core.Auth do
  @moduledoc """
  Public API for authentication. Composes the Auth0 verifier, session token,
  and Auth0 Management API modules behind a stable interface.

  Each collaborator is selected by `Application.get_env(:core, ...)` so tests
  can swap in Mox-backed mocks without touching call sites:

    * `:auth0_verifier`      — defaults to `Core.Auth.Auth0Verifier`
    * `:session_token`       — defaults to `Core.Auth.SessionToken`
    * `:management_api`      — defaults to `Core.Auth.ManagementApi`
  """

  alias Core.Accounts.User
  alias Core.Accounts.Users
  alias Core.Auth.Auth0Verifier
  alias Core.Auth.ManagementApi
  alias Core.Auth.SessionToken

  @doc """
  Verifies an Auth0 access token, upserts the user row from the
  verified claims, and issues this BE's session JWT carrying the
  user's role.

  Email / name / picture come from the Auth0 access token if the
  corresponding standard OIDC claims are present. If they are not,
  the BE falls back to derived values (`<sub>@unknown.local`,
  `<sub>`, `nil`) so the user row can be created on first login. To
  surface real profile data, configure a Post-Login Action to inject
  the OIDC claims onto the access token.

  On success returns the verified `user_sub`, the requested `home_id`
  (echoed for convenience), and the freshly minted session JWT.
  """
  @spec exchange_auth0_token(String.t(), String.t()) ::
          {:ok, %{user_sub: String.t(), home_id: String.t(), session_jwt: String.t()}}
          | {:error, term()}
  def exchange_auth0_token(token, home_id) when is_binary(token) and is_binary(home_id) do
    with {:ok, claims} <- verifier().verify(token),
         {:ok, user_sub} <- fetch_sub(claims),
         {:ok, %User{} = user} <- Users.upsert_from_auth0(user_attrs_from_claims(claims)),
         {:ok, session_jwt} <-
           session_token().issue(build_session_claims(user, home_id)) do
      {:ok, %{user_sub: user_sub, home_id: home_id, session_jwt: session_jwt}}
    else
      {:error, %Ecto.Changeset{}} -> {:error, :user_upsert_failed}
      other -> other
    end
  end

  @doc """
  Verifies a session JWT previously issued by this BE.
  """
  @spec verify_session(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_session(token) when is_binary(token) do
    session_token().verify(token)
  end

  @doc """
  Registers a home for an Auth0 user by patching their `app_metadata.homes`.

  Fetches the user's current `app_metadata`, upserts an entry keyed by
  `home_id` (replacing any existing URL for the same home), and PATCHes the
  merged list back via the Management API. Auth0's `app_metadata` PATCH is a
  shallow merge that replaces nested arrays, so the read-modify-write is
  required for repeated `mix seed.homes` calls to accumulate.
  """
  @spec register_home_for_user(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def register_home_for_user(user_sub, home_id, url)
      when is_binary(user_sub) and is_binary(home_id) and is_binary(url) do
    with {:ok, app_metadata} <- management_api().get_app_metadata(user_sub) do
      current_homes = Map.get(app_metadata, "homes", [])
      updated_homes = upsert_home(current_homes, home_id, url)
      management_api().update_app_metadata(user_sub, %{"homes" => updated_homes})
    end
  end

  defp fetch_sub(%{"sub" => sub}) when is_binary(sub), do: {:ok, sub}
  defp fetch_sub(_claims), do: {:error, :missing_sub_claim}

  defp user_attrs_from_claims(claims) do
    sub = claims["sub"]

    %{
      auth0_sub: sub,
      email: claims["email"] || "#{sub}@unknown.local",
      name: claims["name"] || sub,
      picture: claims["picture"]
    }
  end

  defp build_session_claims(%User{auth0_sub: sub, role: role}, home_id) do
    now = System.system_time(:second)
    %{"sub" => sub, "home_id" => home_id, "role" => role.name, "iat" => now}
  end

  defp upsert_home(homes, home_id, url) do
    rest = Enum.reject(homes, fn entry -> Map.get(entry, "home_id") == home_id end)
    rest ++ [%{"home_id" => home_id, "url" => url}]
  end

  defp verifier do
    Application.get_env(:core, :auth0_verifier, Auth0Verifier)
  end

  defp session_token do
    Application.get_env(:core, :session_token, SessionToken)
  end

  defp management_api do
    Application.get_env(:core, :management_api, ManagementApi)
  end
end
