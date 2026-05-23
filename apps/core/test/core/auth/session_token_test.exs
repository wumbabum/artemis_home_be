defmodule Core.Auth.SessionTokenTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Core.Auth.SessionSigningKey
  alias Core.Auth.SessionToken

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "artemis_session_token_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    original = Application.get_env(:core, :session_signing_key_dir)
    Application.put_env(:core, :session_signing_key_dir, tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)

      if is_nil(original) do
        Application.delete_env(:core, :session_signing_key_dir)
      else
        Application.put_env(:core, :session_signing_key_dir, original)
      end
    end)

    :ok
  end

  describe "issue/1 and verify/1 round trip" do
    test "issues a token and verifies it back to the same claims" do
      assert {:ok, token} = SessionToken.issue(%{"sub" => "auth0|abc", "home_id" => "alpha"})
      assert {:ok, claims} = SessionToken.verify(token)
      assert claims["sub"] == "auth0|abc"
      assert claims["home_id"] == "alpha"
      assert is_integer(claims["iat"])
      assert is_integer(claims["exp"])
      assert claims["exp"] > claims["iat"]
    end
  end

  describe "verify/1 error paths" do
    test "rejects a token whose exp is in the past" do
      past = System.system_time(:second) - 60

      {:ok, token} =
        SessionToken.issue(%{"sub" => "auth0|abc", "home_id" => "alpha", "exp" => past})

      assert {:error, :token_expired} = SessionToken.verify(token)
    end

    test "rejects a token whose claims do not include exp" do
      # Bypass issue/1 so we can build an exp-less token.
      signer = SessionSigningKey.signer!()
      {:ok, token, _} = Joken.encode_and_sign(%{"sub" => "auth0|abc"}, signer)

      assert {:error, :missing_exp} = SessionToken.verify(token)
    end
  end

  describe "property" do
    property "any well-formed claims map round-trips through issue/verify" do
      check all(
              sub <- string(:alphanumeric, min_length: 1, max_length: 20),
              home_id <- string(:alphanumeric, min_length: 1, max_length: 12)
            ) do
        assert {:ok, token} = SessionToken.issue(%{"sub" => sub, "home_id" => home_id})
        assert {:ok, claims} = SessionToken.verify(token)
        assert claims["sub"] == sub
        assert claims["home_id"] == home_id
      end
    end
  end
end
