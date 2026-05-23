defmodule Web.MeControllerTest do
  use Web.ConnCase, async: false

  import Mox

  alias Core.Auth.SessionTokenMock

  setup :set_mox_global
  setup :verify_on_exit!

  describe "GET /api/me/ping" do
    test "returns user_sub, home_id, and admin role for a valid session", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn "valid.session.jwt" ->
        {:ok, %{"sub" => "google-oauth2|abc", "home_id" => "test_home"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.session.jwt")
        |> get(~p"/api/me/ping")

      assert json_response(conn, 200) == %{
               "user_sub" => "google-oauth2|abc",
               "home_id" => "test_home",
               "role" => "admin"
             }
    end

    test "returns 401 when no Authorization header is present", %{conn: conn} do
      conn = get(conn, ~p"/api/me/ping")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "returns 401 when the session token is invalid", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _ -> {:error, :token_expired} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer expired.session.jwt")
        |> get(~p"/api/me/ping")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end
end
