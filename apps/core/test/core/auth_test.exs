defmodule Core.AuthTest do
  use ExUnit.Case, async: false

  import Mox

  alias Core.Accounts.Users
  alias Core.Auth
  alias Core.Auth.Auth0VerifierMock
  alias Core.Auth.ManagementApiMock
  alias Core.Auth.SessionTokenMock
  alias Core.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "exchange_auth0_token/2 happy path" do
    test "verifies the token, upserts the user, and issues a session JWT carrying the role" do
      stub(Auth0VerifierMock, :verify, fn "auth0_access_token" ->
        {:ok,
         %{
           "sub" => "auth0|user-1",
           "email" => "user@example.com",
           "name" => "User One",
           "picture" => "https://cdn.example.com/u1.png",
           "aud" => "https://artemis.app/api"
         }}
      end)

      stub(SessionTokenMock, :issue, fn claims ->
        assert claims["sub"] == "auth0|user-1"
        assert claims["home_id"] == "alpha"
        assert claims["role"] == "guest"
        assert is_integer(claims["iat"])
        {:ok, "session.jwt.value"}
      end)

      assert {:ok,
              %{
                user_sub: "auth0|user-1",
                home_id: "alpha",
                session_jwt: "session.jwt.value"
              }} = Auth.exchange_auth0_token("auth0_access_token", "alpha")

      user = Users.get_user_by_auth0_sub("auth0|user-1")
      assert user.email == "user@example.com"
      assert user.name == "User One"
      assert user.picture == "https://cdn.example.com/u1.png"
    end

    test "falls back to derived email/name when the access token omits OIDC claims" do
      stub(Auth0VerifierMock, :verify, fn _token ->
        {:ok, %{"sub" => "auth0|user-2", "aud" => "https://artemis.app/api"}}
      end)

      stub(SessionTokenMock, :issue, fn claims ->
        assert claims["role"] == "guest"
        {:ok, "session.jwt.value"}
      end)

      assert {:ok, _} = Auth.exchange_auth0_token("auth0_access_token", "alpha")

      user = Users.get_user_by_auth0_sub("auth0|user-2")
      assert user.email == "auth0|user-2@unknown.local"
      assert user.name == "auth0|user-2"
      assert user.picture == nil
    end
  end

  describe "exchange_auth0_token/2 error paths" do
    test "propagates verifier failures" do
      stub(Auth0VerifierMock, :verify, fn _token -> {:error, :invalid_token} end)

      assert {:error, :invalid_token} =
               Auth.exchange_auth0_token("bogus", "alpha")
    end

    test "returns :missing_sub_claim when the verified claims lack a sub" do
      stub(Auth0VerifierMock, :verify, fn _token ->
        {:ok, %{"aud" => "https://artemis.app/api"}}
      end)

      assert {:error, :missing_sub_claim} =
               Auth.exchange_auth0_token("auth0_access_token", "alpha")
    end

    test "propagates SessionToken.issue failures" do
      stub(Auth0VerifierMock, :verify, fn _token ->
        {:ok,
         %{
           "sub" => "auth0|user-3",
           "email" => "u3@example.com",
           "name" => "User Three"
         }}
      end)

      stub(SessionTokenMock, :issue, fn _claims -> {:error, :signing_key_unavailable} end)

      assert {:error, :signing_key_unavailable} =
               Auth.exchange_auth0_token("auth0_access_token", "alpha")
    end

    test "returns :user_upsert_failed when the changeset is invalid" do
      # Name longer than the schema's 255-char cap forces the changeset
      # to fail validation, exercising the changeset-error branch.
      stub(Auth0VerifierMock, :verify, fn _token ->
        {:ok,
         %{
           "sub" => "auth0|user-4",
           "email" => "u4@example.com",
           "name" => String.duplicate("a", 300)
         }}
      end)

      stub(SessionTokenMock, :issue, fn _claims ->
        flunk("SessionToken.issue should not be called when upsert fails")
      end)

      assert {:error, :user_upsert_failed} =
               Auth.exchange_auth0_token("auth0_access_token", "alpha")
    end
  end

  describe "verify_session/1" do
    test "delegates to the SessionToken implementation" do
      stub(SessionTokenMock, :verify, fn "session.jwt.value" ->
        {:ok, %{"sub" => "auth0|user-1", "home_id" => "alpha"}}
      end)

      assert {:ok, %{"sub" => "auth0|user-1", "home_id" => "alpha"}} =
               Auth.verify_session("session.jwt.value")
    end

    test "propagates verification failures" do
      stub(SessionTokenMock, :verify, fn _token -> {:error, :token_expired} end)

      assert {:error, :token_expired} = Auth.verify_session("expired.token.value")
    end
  end

  describe "register_home_for_user/3" do
    test "appends a new home when none exist for the user" do
      test_pid = self()

      stub(ManagementApiMock, :get_app_metadata, fn "auth0|user-1" -> {:ok, %{}} end)

      stub(ManagementApiMock, :update_app_metadata, fn "auth0|user-1", patch ->
        send(test_pid, {:updated, patch})
        {:ok, %{"app_metadata" => patch}}
      end)

      assert {:ok, _} =
               Auth.register_home_for_user("auth0|user-1", "alpha", "http://localhost:4001")

      assert_received {:updated,
                       %{"homes" => [%{"home_id" => "alpha", "url" => "http://localhost:4001"}]}}
    end

    test "appends a new home when other distinct homes already exist" do
      test_pid = self()

      stub(ManagementApiMock, :get_app_metadata, fn _sub ->
        {:ok, %{"homes" => [%{"home_id" => "alpha", "url" => "http://localhost:4001"}]}}
      end)

      stub(ManagementApiMock, :update_app_metadata, fn _sub, patch ->
        send(test_pid, {:updated, patch})
        {:ok, %{}}
      end)

      assert {:ok, _} =
               Auth.register_home_for_user("auth0|user-1", "beta", "http://localhost:4002")

      assert_received {:updated, %{"homes" => homes}}
      assert length(homes) == 2
      assert %{"home_id" => "alpha", "url" => "http://localhost:4001"} in homes
      assert %{"home_id" => "beta", "url" => "http://localhost:4002"} in homes
    end

    test "replaces the URL when re-registering an existing home_id" do
      test_pid = self()

      stub(ManagementApiMock, :get_app_metadata, fn _sub ->
        {:ok,
         %{
           "homes" => [
             %{"home_id" => "alpha", "url" => "http://old.invalid"},
             %{"home_id" => "beta", "url" => "http://localhost:4002"}
           ]
         }}
      end)

      stub(ManagementApiMock, :update_app_metadata, fn _sub, patch ->
        send(test_pid, {:updated, patch})
        {:ok, %{}}
      end)

      assert {:ok, _} =
               Auth.register_home_for_user("auth0|user-1", "alpha", "http://localhost:4001")

      assert_received {:updated, %{"homes" => homes}}
      assert length(homes) == 2
      assert %{"home_id" => "alpha", "url" => "http://localhost:4001"} in homes
      assert %{"home_id" => "beta", "url" => "http://localhost:4002"} in homes
      refute Enum.any?(homes, fn entry -> Map.get(entry, "url") == "http://old.invalid" end)
    end

    test "propagates errors from get_app_metadata without calling update_app_metadata" do
      stub(ManagementApiMock, :get_app_metadata, fn _sub ->
        {:error, {:http_status, 404, %{"error" => "Not Found"}}}
      end)

      stub(ManagementApiMock, :update_app_metadata, fn _sub, _patch ->
        flunk("update_app_metadata should not be called when get_app_metadata fails")
      end)

      assert {:error, {:http_status, 404, %{"error" => "Not Found"}}} =
               Auth.register_home_for_user("auth0|user-1", "alpha", "http://localhost:4001")
    end

    test "propagates errors from update_app_metadata" do
      stub(ManagementApiMock, :get_app_metadata, fn _sub -> {:ok, %{}} end)

      stub(ManagementApiMock, :update_app_metadata, fn _sub, _patch ->
        {:error, :auth0_unreachable}
      end)

      assert {:error, :auth0_unreachable} =
               Auth.register_home_for_user("auth0|user-1", "alpha", "http://localhost:4001")
    end
  end
end
