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

  describe "verify/1" do
    test "returns claims for a valid token signed by the cached key", %{keypair: keypair} do
      token = Auth0TokenHelper.sign(keypair, Auth0TokenHelper.default_claims())

      assert {:ok, claims} = Auth0Verifier.verify(token)
      assert claims["sub"] == "auth0|test-user"
      assert claims["aud"] == "https://artemis.app/api"
    end

    test "rejects tokens whose homes claim does not include this BE's home_id",
         %{keypair: keypair} do
      claims =
        Auth0TokenHelper.default_claims(
          "https://artemis.app/homes": [%{"home_id" => "different_home"}]
        )

      token = Auth0TokenHelper.sign(keypair, claims)

      assert {:error, :home_not_authorized} = Auth0Verifier.verify(token)
    end
  end
end
