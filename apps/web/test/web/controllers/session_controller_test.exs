defmodule Web.SessionControllerTest do
  use Web.ConnCase, async: false

  import Mox

  alias Core.Auth.Auth0VerifierMock
  alias Core.Auth.SessionTokenMock

  setup :set_mox_global
  setup :verify_on_exit!

  describe "POST /api/sessions happy path" do
    test "exchanges a valid Auth0 token for a session JWT", %{conn: conn} do
      stub(Auth0VerifierMock, :verify, fn "auth0.access.token" ->
        {:ok,
         %{
           "sub" => "google-oauth2|abc",
           "iss" => "https://test.auth0.com/",
           "aud" => "https://artemis.app/api",
           "https://artemis.app/homes" => [%{"home_id" => "test_home"}]
         }}
      end)

      stub(SessionTokenMock, :issue, fn claims ->
        assert claims["sub"] == "google-oauth2|abc"
        assert claims["home_id"] == "test_home"
        {:ok, "issued.session.jwt"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer auth0.access.token")
        |> post(~p"/api/sessions")

      assert json_response(conn, 200) == %{
               "user_sub" => "google-oauth2|abc",
               "home_id" => "test_home",
               "session_jwt" => "issued.session.jwt"
             }
    end
  end

  describe "POST /api/sessions error responses" do
    test "returns 400 when the Authorization header is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/sessions")

      assert json_response(conn, 400) == %{"error" => "missing_bearer"}
    end

    test "returns 400 when the Authorization header is not a Bearer token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic Zm9vOmJhcg==")
        |> post(~p"/api/sessions")

      assert json_response(conn, 400) == %{"error" => "missing_bearer"}
    end

    test "returns 401 when Auth0 verifier rejects the token", %{conn: conn} do
      stub(Auth0VerifierMock, :verify, fn _ -> {:error, :token_expired} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer expired.token")
        |> post(~p"/api/sessions")

      assert json_response(conn, 401) == %{"error" => "token_expired"}
    end

    test "returns 401 with a generic shape for invalid issuer", %{conn: conn} do
      stub(Auth0VerifierMock, :verify, fn _ -> {:error, :invalid_iss} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bad.iss")
        |> post(~p"/api/sessions")

      assert json_response(conn, 401) == %{"error" => "invalid_iss"}
    end

    test "returns 403 when the user's homes claim excludes this BE's HOME_ID",
         %{conn: conn} do
      stub(Auth0VerifierMock, :verify, fn _ -> {:error, :home_not_authorized} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.but.wrong.home")
        |> post(~p"/api/sessions")

      assert json_response(conn, 403) == %{"error" => "home_not_authorized"}
    end

    test "returns 503 on unexpected upstream errors (Auth0 unreachable)", %{conn: conn} do
      stub(Auth0VerifierMock, :verify, fn _ -> {:error, :nxdomain} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.token")
        |> post(~p"/api/sessions")

      assert json_response(conn, 503) == %{"error" => "auth0_unreachable"}
    end

    test "returns 503 when the BE has no HOME_ID configured", %{conn: conn} do
      original = Application.get_env(:core, :home_id)
      Application.delete_env(:core, :home_id)
      on_exit(fn -> Application.put_env(:core, :home_id, original) end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any.token")
        |> post(~p"/api/sessions")

      assert json_response(conn, 503) == %{"error" => "misconfigured"}
    end
  end
end
