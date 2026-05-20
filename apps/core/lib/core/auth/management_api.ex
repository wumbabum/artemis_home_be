defmodule Core.Auth.ManagementApi do
  @moduledoc """
  Wraps the Auth0 Management API. The only operation needed by v0 is patching
  a user's `app_metadata` with their list of registered homes.

  Acquires a Machine-to-Machine (M2M) token via the client_credentials grant
  on the first call and caches it in `:persistent_term` for roughly 85% of
  the token's reported `expires_in` so we refresh well before Auth0 rejects
  it. Subsequent calls within that window reuse the cached token.

  Higher layers should mock this module via Mox (the behaviour is defined
  here) instead of reaching into the HTTP client directly.
  """

  @callback update_app_metadata(user_sub :: String.t(), patch :: map()) ::
              {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

  @cache_key {__MODULE__, :m2m_token}
  # Refresh M2M tokens at 85% of their reported lifetime to avoid using a
  # token that's about to be rejected by Auth0.
  @cache_fraction 0.85

  @impl true
  @spec update_app_metadata(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_app_metadata(user_sub, patch) when is_binary(user_sub) and is_map(patch) do
    with {:ok, domain} <- fetch_config(:auth0_domain),
         {:ok, token} <- fetch_or_refresh_token(domain) do
      http_client().patch_user(domain, token, user_sub, %{"app_metadata" => patch})
    end
  end

  @doc """
  Drops the cached M2M token. Intended for tests; production code never needs
  to call this directly.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    _ = :persistent_term.erase(@cache_key)
    :ok
  end

  defp fetch_or_refresh_token(domain) do
    now = System.system_time(:second)

    case :persistent_term.get(@cache_key, :none) do
      {token, expires_at} when expires_at > now -> {:ok, token}
      _ -> refresh_token(domain, now)
    end
  end

  defp refresh_token(domain, now) do
    with {:ok, client_id} <- fetch_config(:auth0_m2m_client_id),
         {:ok, client_secret} <- fetch_config(:auth0_m2m_client_secret),
         {:ok, %{access_token: token, expires_in: expires_in}} <-
           http_client().fetch_token(domain, client_id, client_secret) do
      ttl = trunc(expires_in * @cache_fraction)
      :persistent_term.put(@cache_key, {token, now + ttl})
      {:ok, token}
    end
  end

  defp fetch_config(key) do
    case Application.get_env(:core, key) do
      nil -> {:error, {:missing_config, key}}
      value -> {:ok, value}
    end
  end

  defp http_client do
    Application.get_env(
      :core,
      :management_api_http_client,
      Core.Auth.ManagementApi.HttpClient
    )
  end
end
