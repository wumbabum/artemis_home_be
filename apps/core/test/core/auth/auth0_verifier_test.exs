defmodule Core.Auth.Auth0VerifierTest do
  use ExUnit.Case, async: false

  import Mox

  alias Core.Auth.Auth0TokenHelper
  alias Core.Auth.Auth0Verifier
  alias Core.Auth.JwksCacheMock

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    keypair = Auth0TokenHelper.generate_keypair()
    stub(JwksCacheMock, :fetch, fn _kid -> {:ok, keypair.public_jwk_map} end)
    %{keypair: keypair}
  end

  describe "verify/1 happy path" do
    test "returns claims for a valid token signed by the cached key", %{keypair: keypair} do
      token = Auth0TokenHelper.sign(keypair, Auth0TokenHelper.default_claims())

      assert {:ok, claims} = Auth0Verifier.verify(token)
      assert claims["sub"] == "auth0|test-user"
      assert claims["aud"] == "https://artemis.app/api"
    end

    test "accepts an aud claim that is a list containing the configured audience",
         %{keypair: keypair} do
      claims =
        Auth0TokenHelper.default_claims(
          aud: ["https://artemis.app/api", "https://some-other.api"]
        )

      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:ok, _} = Auth0Verifier.verify(token)
    end
  end

  describe "verify/1 header errors" do
    test "returns :missing_kid when the token header has no kid", %{keypair: keypair} do
      token = Auth0TokenHelper.sign_without_kid(keypair, Auth0TokenHelper.default_claims())

      assert {:error, :missing_kid} = Auth0Verifier.verify(token)
    end

    test "returns :invalid_token for a malformed token string" do
      assert {:error, :invalid_token} = Auth0Verifier.verify("not.a.real.token")
    end
  end

  describe "verify/1 issuer validation" do
    test "rejects a token whose iss does not match the configured Auth0 domain",
         %{keypair: keypair} do
      claims = Auth0TokenHelper.default_claims(iss: "https://imposter.auth0.com/")
      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :invalid_iss} = Auth0Verifier.verify(token)
    end

    test "rejects a token with no iss claim", %{keypair: keypair} do
      claims = Auth0TokenHelper.default_claims() |> Map.delete("iss")
      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :missing_iss} = Auth0Verifier.verify(token)
    end
  end

  describe "verify/1 audience validation" do
    test "rejects a token whose aud is wrong", %{keypair: keypair} do
      claims = Auth0TokenHelper.default_claims(aud: "https://other.example.com")
      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :invalid_aud} = Auth0Verifier.verify(token)
    end

    test "rejects a token with no aud claim", %{keypair: keypair} do
      claims = Auth0TokenHelper.default_claims() |> Map.delete("aud")
      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :missing_aud} = Auth0Verifier.verify(token)
    end

    test "fails fast when the BE has no audience configured", %{keypair: keypair} do
      original = Application.get_env(:core, :auth0_audience)
      Application.delete_env(:core, :auth0_audience)
      on_exit(fn -> Application.put_env(:core, :auth0_audience, original) end)

      token = Auth0TokenHelper.sign(keypair, Auth0TokenHelper.default_claims())

      assert {:error, :missing_aud_config} = Auth0Verifier.verify(token)
    end
  end

  describe "verify/1 expiry validation" do
    test "rejects an expired token", %{keypair: keypair} do
      claims = Auth0TokenHelper.default_claims(exp: System.system_time(:second) - 60)
      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :token_expired} = Auth0Verifier.verify(token)
    end

    test "rejects a token with no exp claim", %{keypair: keypair} do
      claims = Auth0TokenHelper.default_claims() |> Map.delete("exp")
      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :missing_exp} = Auth0Verifier.verify(token)
    end
  end

  describe "verify/1 home validation" do
    test "rejects tokens whose homes claim does not include this BE's home_id",
         %{keypair: keypair} do
      claims =
        Auth0TokenHelper.default_claims(
          "https://artemis.app/homes": [%{"home_id" => "different_home"}]
        )

      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :home_not_authorized} = Auth0Verifier.verify(token)
    end

    test "fails fast when the BE has no home_id configured", %{keypair: keypair} do
      original = Application.get_env(:core, :home_id)
      Application.delete_env(:core, :home_id)
      on_exit(fn -> Application.put_env(:core, :home_id, original) end)

      token = Auth0TokenHelper.sign(keypair, Auth0TokenHelper.default_claims())

      assert {:error, :missing_home_id_config} = Auth0Verifier.verify(token)
    end
  end
end
