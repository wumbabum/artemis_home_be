defmodule Web.Plugs.RequireSessionTest do
  use Web.ConnCase, async: false

  import Mox

  alias Core.Auth.SessionTokenMock
  alias Web.Plugs.RequireSession

  setup :set_mox_global
  setup :verify_on_exit!

  describe "init/1" do
    test "returns the opts unchanged" do
      assert RequireSession.init([]) == []
      assert RequireSession.init(some: :opt) == [some: :opt]
    end
  end

  describe "valid bearer token" do
    test "assigns current_user from verified claims and does not halt", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn "valid.session.jwt" ->
        {:ok, %{"sub" => "google-oauth2|abc", "home_id" => "alpha", "role" => "admin"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.session.jwt")
        |> RequireSession.call([])

      assert conn.assigns.current_user == %{
               user_sub: "google-oauth2|abc",
               home_id: "alpha",
               role: "admin"
             }

      refute conn.halted
    end

    test "passes through extra claims without exposing them on current_user", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _token ->
        {:ok,
         %{
           "sub" => "google-oauth2|abc",
           "home_id" => "alpha",
           "role" => "guest",
           "iat" => 1_700_000_000,
           "exp" => 1_700_003_600,
           "extra" => "ignored"
         }}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.session.jwt")
        |> RequireSession.call([])

      assert conn.assigns.current_user == %{
               user_sub: "google-oauth2|abc",
               home_id: "alpha",
               role: "guest"
             }
    end
  end

  describe "missing or malformed authorization header" do
    test "returns 401 when no Authorization header is present", %{conn: conn} do
      conn = RequireSession.call(conn, [])

      assert_unauthorized(conn)
    end

    test "returns 401 when the Authorization header is not Bearer", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic Zm9vOmJhcg==")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end

    test "returns 401 when the Bearer prefix is present but the token is empty", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end
  end

  describe "session token rejected by Core.Auth" do
    test "returns 401 on :token_expired", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _ -> {:error, :token_expired} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer expired.token")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end

    test "returns 401 on a signature failure", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _ -> {:error, :signature_error} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bogus.token")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end
  end

  describe "claims missing required fields" do
    test "returns 401 when sub is missing", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _ ->
        {:ok, %{"home_id" => "alpha", "role" => "admin"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.token")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end

    test "returns 401 when home_id is missing", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _ ->
        {:ok, %{"sub" => "google-oauth2|abc", "role" => "admin"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.token")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end

    test "returns 401 when role is missing (v0 session JWT)", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _ ->
        {:ok, %{"sub" => "google-oauth2|abc", "home_id" => "alpha"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.token")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end

    test "returns 401 when sub or home_id is not a binary", %{conn: conn} do
      stub(SessionTokenMock, :verify, fn _ ->
        {:ok, %{"sub" => "google-oauth2|abc", "home_id" => 42, "role" => "admin"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid.token")
        |> RequireSession.call([])

      assert_unauthorized(conn)
    end
  end

  defp assert_unauthorized(conn) do
    assert conn.halted
    assert conn.status == 401
    assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
  end
end
