defmodule Core.Auth.Auth0TokenHelper do
  @moduledoc """
  Generates RSA-signed JWTs and matching JWKS entries for testing the
  Auth0 verifier without touching a real Auth0 tenant.
  """

  @type keypair :: %{private_jwk: term(), public_jwk_map: map(), kid: String.t()}

  @doc """
  Generates a fresh RSA-2048 keypair and packages the public half as a JWK map
  ready for stubbing into a JwksCache.
  """
  @spec generate_keypair(String.t()) :: keypair()
  def generate_keypair(kid \\ "test-kid") do
    private_jwk = JOSE.JWK.generate_key({:rsa, 2048})
    public_jwk = JOSE.JWK.to_public(private_jwk)
    {_, public_jwk_map} = JOSE.JWK.to_map(public_jwk)

    public_jwk_map_with_kid =
      Map.merge(public_jwk_map, %{"kid" => kid, "use" => "sig", "alg" => "RS256"})

    %{private_jwk: private_jwk, public_jwk_map: public_jwk_map_with_kid, kid: kid}
  end

  @doc """
  Signs the given claims with the keypair, producing a compact-form JWT string.
  """
  @spec sign(keypair(), map()) :: String.t()
  def sign(%{private_jwk: jwk, kid: kid}, claims) do
    signer = Joken.Signer.create("RS256", %{"pem" => to_pem(jwk)}, %{"kid" => kid})
    {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)
    token
  end

  @doc """
  Signs claims using the keypair but emits a JWS header without a `kid` field.
  Used to test the verifier's :missing_kid path.
  """
  @spec sign_without_kid(keypair(), map()) :: String.t()
  def sign_without_kid(%{private_jwk: jwk}, claims) do
    signer = Joken.Signer.create("RS256", %{"pem" => to_pem(jwk)})
    {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)
    token
  end

  defp to_pem(jwk) do
    {_, pem} = JOSE.JWK.to_pem(jwk)
    pem
  end

  @doc """
  Builds a default set of claims that match what Auth0 issues for our config,
  with sane defaults that callers can override.
  """
  @spec default_claims(keyword()) :: map()
  def default_claims(overrides \\ []) do
    now = System.system_time(:second)

    base = %{
      "iss" => "https://test.auth0.com/",
      "aud" => "https://artemis.app/api",
      "sub" => "auth0|test-user",
      "iat" => now,
      "exp" => now + 3600,
      "https://artemis.app/homes" => [
        %{"home_id" => "test_home", "url" => "http://localhost:4001"}
      ]
    }

    Enum.reduce(overrides, base, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)
  end
end
