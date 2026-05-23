defmodule Core.Auth.JwksCache.HttpFetcher do
  @moduledoc """
  Default JWKS fetcher: an HTTP GET against the Auth0 tenant's JWKS endpoint.

  Tests swap this implementation for a Mox via `:core`'s `:jwks_fetcher`
  application env.
  """

  @callback fetch_jwks(domain :: String.t() | nil) :: {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def fetch_jwks(nil), do: {:error, :missing_auth0_domain}

  def fetch_jwks(domain) when is_binary(domain) do
    url = "https://" <> domain <> "/.well-known/jwks.json"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
