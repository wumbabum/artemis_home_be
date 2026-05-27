defmodule Web.HomeControllerTest do
  use Web.ConnCase, async: false

  import Mox

  alias Core.Auth.SessionTokenMock
  alias Core.HA.RestClientMock

  setup :set_mox_global
  setup :verify_on_exit!

  defp authed(conn, role \\ "admin") do
    stub(SessionTokenMock, :verify, fn "session.jwt" ->
      {:ok, %{"sub" => "google-oauth2|abc", "home_id" => "test_home", "role" => role}}
    end)

    conn
    |> put_req_header("authorization", "Bearer session.jwt")
    |> put_req_header("content-type", "application/json")
  end

  defp zwave_entry(overrides \\ %{}) do
    Map.merge(
      %{
        "domain" => "zwave_js",
        "entry_id" => "01KBTT53FXENZ9JQM6BF8JY9MQ",
        "title" => "Z-Wave JS",
        "state" => "loaded",
        "reason" => nil,
        "disabled_by" => nil
      },
      overrides
    )
  end

  describe "GET /api/home happy path" do
    test "returns home metadata + zwave available when HA reports loaded", %{conn: conn} do
      expect(RestClientMock, :list_config_entries, fn "zwave_js" -> {:ok, [zwave_entry()]} end)

      conn = conn |> authed("admin") |> get(~p"/api/home")

      assert json_response(conn, 200) == %{
               "user_sub" => "google-oauth2|abc",
               "home_id" => "test_home",
               "role" => "admin",
               "integrations" => %{
                 "zwave" => %{
                   "available" => true,
                   "state" => "loaded",
                   "reason" => nil,
                   "title" => "Z-Wave JS"
                 }
               }
             }
    end

    test "uses the role and user_sub from the verified session JWT", %{conn: conn} do
      stub(RestClientMock, :list_config_entries, fn _ -> {:ok, [zwave_entry()]} end)

      conn = conn |> authed("guest") |> get(~p"/api/home")

      assert %{"role" => "guest", "user_sub" => "google-oauth2|abc"} =
               json_response(conn, 200)
    end
  end

  describe "GET /api/home zwave-not-available cases" do
    test "reports reason=not_installed when HA returns an empty list", %{conn: conn} do
      stub(RestClientMock, :list_config_entries, fn _ -> {:ok, []} end)

      conn = conn |> authed() |> get(~p"/api/home")

      assert %{"integrations" => %{"zwave" => zw}} = json_response(conn, 200)

      assert zw == %{
               "available" => false,
               "state" => nil,
               "reason" => "not_installed",
               "title" => nil
             }
    end

    test "reports reason=disabled_in_ha when disabled_by is set", %{conn: conn} do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:ok, [zwave_entry(%{"disabled_by" => "user", "state" => "not_loaded"})]}
      end)

      conn = conn |> authed() |> get(~p"/api/home")

      assert %{"integrations" => %{"zwave" => zw}} = json_response(conn, 200)
      assert zw["available"] == false
      assert zw["reason"] == "disabled_in_ha"
      assert zw["state"] == "not_loaded"
      assert zw["title"] == "Z-Wave JS"
    end

    test "surfaces HA's setup_error reason verbatim", %{conn: conn} do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:ok,
         [
           zwave_entry(%{
             "state" => "setup_error",
             "reason" => "Z-Wave JS Server unreachable"
           })
         ]}
      end)

      conn = conn |> authed() |> get(~p"/api/home")

      assert %{"integrations" => %{"zwave" => zw}} = json_response(conn, 200)
      assert zw["available"] == false
      assert zw["reason"] == "Z-Wave JS Server unreachable"
      assert zw["state"] == "setup_error"
    end
  end

  describe "GET /api/home HA-error tolerance" do
    test "returns 200 with reason=ha_unreachable when HA transport fails", %{conn: conn} do
      stub(RestClientMock, :list_config_entries, fn _ -> {:error, :ha_unreachable} end)

      conn = conn |> authed() |> get(~p"/api/home")

      body = json_response(conn, 200)

      # home identity is still returned even when HA is down
      assert body["user_sub"] == "google-oauth2|abc"
      assert body["home_id"] == "test_home"
      assert body["role"] == "admin"

      assert body["integrations"]["zwave"] == %{
               "available" => false,
               "state" => nil,
               "reason" => "ha_unreachable",
               "title" => nil
             }
    end

    test "returns 200 with reason=ha_status when HA returns a non-2xx", %{conn: conn} do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:error, {:ha_status, 500, %{"message" => "boom"}}}
      end)

      conn = conn |> authed() |> get(~p"/api/home")

      assert %{"integrations" => %{"zwave" => zw}} = json_response(conn, 200)
      assert zw["reason"] == "ha_status"
      assert zw["available"] == false
    end

    test "returns 200 with reason=unknown for any other HA error shape", %{conn: conn} do
      stub(RestClientMock, :list_config_entries, fn _ -> {:error, :something_weird} end)

      conn = conn |> authed() |> get(~p"/api/home")

      assert %{"integrations" => %{"zwave" => zw}} = json_response(conn, 200)
      assert zw["reason"] == "unknown"
      assert zw["available"] == false
    end
  end

  describe "GET /api/home authentication" do
    test "returns 401 without a session", %{conn: conn} do
      conn = get(conn, ~p"/api/home")
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end
end
