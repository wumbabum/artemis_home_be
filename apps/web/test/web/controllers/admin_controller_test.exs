defmodule Web.AdminControllerTest do
  use Web.ConnCase, async: false

  import Mox

  alias Core.Auth.ManagementApiMock
  alias Core.Auth.SessionTokenMock

  setup :set_mox_global
  setup :verify_on_exit!

  setup %{conn: conn} do
    # All admin routes go through the :authenticated pipeline, which
    # routes the bearer token through Core.Auth.verify_session.
    stub(SessionTokenMock, :verify, fn "valid.session.jwt" ->
      {:ok, %{"sub" => "google-oauth2|abc", "home_id" => "test_home", "role" => "admin"}}
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid.session.jwt")
      |> put_req_header("content-type", "application/json")

    %{conn: conn}
  end

  describe "POST /api/admin/register-home happy path" do
    test "upserts the home and echoes it back", %{conn: conn} do
      stub(ManagementApiMock, :get_app_metadata, fn "google-oauth2|abc" -> {:ok, %{}} end)

      stub(ManagementApiMock, :update_app_metadata, fn "google-oauth2|abc", patch ->
        assert patch == %{
                 "homes" => [%{"home_id" => "alpha", "url" => "http://localhost:6565"}]
               }

        {:ok, %{}}
      end)

      conn =
        post(conn, ~p"/api/admin/register-home", %{home_id: "alpha", url: "http://localhost:6565"})

      assert json_response(conn, 200) == %{
               "home_id" => "alpha",
               "url" => "http://localhost:6565"
             }
    end
  end

  describe "POST /api/admin/register-home request validation" do
    test "returns 400 when home_id is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/admin/register-home", %{url: "http://localhost:6565"})

      assert json_response(conn, 400) == %{"error" => "missing_home_id"}
    end

    test "returns 400 when url is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/admin/register-home", %{home_id: "alpha"})

      assert json_response(conn, 400) == %{"error" => "missing_url"}
    end

    test "returns 400 when home_id is an empty string", %{conn: conn} do
      conn =
        post(conn, ~p"/api/admin/register-home", %{home_id: "", url: "http://localhost:6565"})

      assert json_response(conn, 400) == %{"error" => "missing_home_id"}
    end

    test "returns 400 when home_id is not a string", %{conn: conn} do
      conn =
        post(conn, ~p"/api/admin/register-home", %{home_id: 42, url: "http://localhost:6565"})

      assert json_response(conn, 400) == %{"error" => "missing_home_id"}
    end
  end

  describe "POST /api/admin/register-home upstream errors" do
    test "returns 503 when Core.Auth.register_home_for_user errors", %{conn: conn} do
      stub(ManagementApiMock, :get_app_metadata, fn _ ->
        {:error, :auth0_unreachable}
      end)

      stub(ManagementApiMock, :update_app_metadata, fn _, _ ->
        flunk("update_app_metadata should not be called when get_app_metadata fails")
      end)

      conn =
        post(conn, ~p"/api/admin/register-home", %{home_id: "alpha", url: "http://localhost:6565"})

      assert json_response(conn, 503) == %{"error" => "auth0_unreachable"}
    end
  end

  describe "POST /api/admin/register-home authentication" do
    test "returns 401 when no session bearer is supplied", %{conn: conn} do
      # Strip the auth header set in the describe-level setup.
      conn = delete_req_header(conn, "authorization")

      conn =
        post(conn, ~p"/api/admin/register-home", %{home_id: "alpha", url: "http://localhost:6565"})

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end
end
