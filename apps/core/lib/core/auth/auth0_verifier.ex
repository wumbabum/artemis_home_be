defmodule Core.Auth.Auth0Verifier do
  @moduledoc """
  Verifies an Auth0-issued access token.

  Checks (in order):

    1. Token parses and has a `kid` in its header.
    2. The JWK for that `kid` exists in the configured JWKS cache.
    3. The token's RS256 signature matches the public key.
    4. `iss` matches `https://<auth0_domain>/`.
    5. `aud` contains the configured audience.
    6. `exp` is in the future.
    7. The `https://artemis.app/homes` custom claim contains an entry whose
       `home_id` matches this BE's configured `home_id`.

  Higher layers should mock this module (it defines a behaviour) rather than
  reaching into `JwksCache` directly.
  """

  @callback verify(token :: String.t()) :: {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def verify(token) when is_binary(token) do
    with {:ok, kid} <- peek_kid(token),
         {:ok, jwk} <- jwks_cache().fetch(kid),
         signer = Joken.Signer.create("RS256", %{"pem" => jwk_to_pem(jwk)}),
         {:ok, claims} <- Joken.verify(token, signer),
         :ok <- validate_iss(claims),
         :ok <- validate_aud(claims),
         :ok <- validate_exp(claims),
         :ok <- validate_home(claims) do
      {:ok, claims}
    end
  end

  defp peek_kid(token) do
    case Joken.peek_header(token) do
      {:ok, %{"kid" => kid}} when is_binary(kid) -> {:ok, kid}
      {:ok, _} -> {:error, :missing_kid}
      {:error, _} -> {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  defp jwk_to_pem(jwk_map) do
    {_, pem} = JOSE.JWK.from_map(jwk_map) |> JOSE.JWK.to_pem()
    pem
  end

  defp validate_iss(%{"iss" => iss}) do
    expected = "https://" <> (Application.get_env(:core, :auth0_domain) || "") <> "/"
    if iss == expected, do: :ok, else: {:error, :invalid_iss}
  end

  defp validate_iss(_claims), do: {:error, :missing_iss}

  defp validate_aud(%{"aud" => aud}) do
    expected = Application.get_env(:core, :auth0_audience)

    cond do
      is_nil(expected) -> {:error, :missing_aud_config}
      aud == expected -> :ok
      is_list(aud) and expected in aud -> :ok
      true -> {:error, :invalid_aud}
    end
  end

  defp validate_aud(_claims), do: {:error, :missing_aud}

  defp validate_exp(%{"exp" => exp}) when is_integer(exp) do
    if exp > System.system_time(:second), do: :ok, else: {:error, :token_expired}
  end

  defp validate_exp(_claims), do: {:error, :missing_exp}

  defp validate_home(claims) do
    home_id = Application.get_env(:core, :home_id)
    homes = Map.get(claims, "https://artemis.app/homes", [])

    cond do
      is_nil(home_id) -> {:error, :missing_home_id_config}
      Enum.any?(homes, &match?(%{"home_id" => ^home_id}, &1)) -> :ok
      true -> {:error, :home_not_authorized}
    end
  end

  defp jwks_cache, do: Application.get_env(:core, :jwks_cache, Core.Auth.JwksCache)
end
