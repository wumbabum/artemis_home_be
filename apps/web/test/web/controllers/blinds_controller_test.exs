defmodule Web.BlindsControllerTest do
  use Web.ConnCase, async: false

  import Mox

  alias Core.Auth.SessionTokenMock
  alias Core.Blinds
  alias Core.Blinds.StateCache
  alias Core.HA.RestClientMock

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # StateCache under the default name so Core.Blinds.* and the
    # controller's StateCache.get_all/0 both resolve to one process.
    start_supervised!({StateCache, name: Core.Blinds.StateCache, poll_interval_ms: :manual})

    # Default: any list_states polls during a test return empty so
    # adaptive refreshes after a write don't surprise other expects.
    stub(RestClientMock, :list_states, fn -> {:ok, []} end)

    :ok
  end

  defp authed(conn, role) do
    stub(SessionTokenMock, :verify, fn "session.jwt" ->
      {:ok, %{"sub" => "google-oauth2|abc", "home_id" => "test_home", "role" => role}}
    end)

    conn
    |> put_req_header("authorization", "Bearer session.jwt")
    |> put_req_header("content-type", "application/json")
  end

  defp create_blind!(attrs \\ %{}) do
    {:ok, blind} =
      Blinds.create_blind(
        Map.merge(
          %{
            name: "Left Window Blind",
            ha_entity_id: "cover.living_room_left",
            manufacturer: "SmartWings",
            protocol: "zwave",
            sort_order: 0
          },
          attrs
        )
      )

    blind
  end

  describe "GET /api/blinds" do
    test "returns the list of blinds ordered by sort_order, then id", %{conn: conn} do
      a = create_blind!(%{name: "A", ha_entity_id: "cover.a", sort_order: 2})
      b = create_blind!(%{name: "B", ha_entity_id: "cover.b", sort_order: 1})
      c = create_blind!(%{name: "C", ha_entity_id: "cover.c", sort_order: 1})

      conn =
        conn
        |> authed("guest")
        |> get(~p"/api/blinds")

      assert [%{"id" => b_id}, %{"id" => c_id}, %{"id" => a_id}] = json_response(conn, 200)
      assert b_id == b.id
      assert c_id == c.id
      assert a_id == a.id
    end

    test "returns 401 without a valid session", %{conn: conn} do
      conn = get(conn, ~p"/api/blinds")
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "GET /api/blinds/states" do
    test "merges cache entries with the DB blinds list", %{conn: conn} do
      blind = create_blind!(%{ha_entity_id: "cover.tv_right"})

      stub(RestClientMock, :list_states, fn ->
        {:ok,
         [
           %{
             "entity_id" => "cover.tv_right",
             "state" => "open",
             "attributes" => %{"current_position" => 65}
           }
         ]}
      end)

      :ok = StateCache.refresh_now(Core.Blinds.StateCache)

      conn =
        conn
        |> authed("guest")
        |> get(~p"/api/blinds/states")

      assert [row] = json_response(conn, 200)

      assert row == %{
               "id" => blind.id,
               "ha_entity_id" => "cover.tv_right",
               "state" => "open",
               "position" => 65,
               "available" => true
             }
    end

    test "returns blinds without a cache entry as unavailable", %{conn: conn} do
      blind = create_blind!(%{ha_entity_id: "cover.never_cached"})

      conn =
        conn
        |> authed("guest")
        |> get(~p"/api/blinds/states")

      assert [row] = json_response(conn, 200)

      assert row == %{
               "id" => blind.id,
               "ha_entity_id" => "cover.never_cached",
               "state" => nil,
               "position" => nil,
               "available" => false
             }
    end
  end

  describe "POST /api/blinds/:id/position" do
    test "calls HA's set_cover_position and returns 204 on success", %{conn: conn} do
      blind = create_blind!()

      expect(RestClientMock, :call_service, fn "cover", "set_cover_position", body ->
        assert body == %{"entity_id" => blind.ha_entity_id, "position" => 30}
        {:ok, []}
      end)

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/position", %{position: 30})

      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns 400 invalid_position for non-integer positions", %{conn: conn} do
      blind = create_blind!()

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/position", %{position: "50"})

      assert json_response(conn, 400) == %{"error" => "invalid_position"}
    end

    test "returns 400 invalid_position when the position is out of range", %{conn: conn} do
      blind = create_blind!()

      stub(RestClientMock, :call_service, fn _, _, _ ->
        flunk("HA service should not be invoked for an out-of-range position")
      end)

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/position", %{position: 200})

      assert json_response(conn, 400) == %{"error" => "invalid_position"}
    end

    test "returns 404 not_found for an unknown blind id", %{conn: conn} do
      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/999999/position", %{position: 50})

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "returns 404 bad_id for an unparseable id", %{conn: conn} do
      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/abc/position", %{position: 50})

      assert json_response(conn, 404) == %{"error" => "bad_id"}
    end

    test "returns 503 ha_unreachable when HA transport fails", %{conn: conn} do
      blind = create_blind!()

      expect(RestClientMock, :call_service, fn _, _, _ -> {:error, :ha_unreachable} end)

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/position", %{position: 50})

      assert json_response(conn, 503) == %{"error" => "ha_unreachable"}
    end

    test "returns 503 ha_status when HA returns a non-2xx status", %{conn: conn} do
      blind = create_blind!()

      expect(RestClientMock, :call_service, fn _, _, _ ->
        {:error, {:ha_status, 503, %{"message" => "boom"}}}
      end)

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/position", %{position: 50})

      assert json_response(conn, 503) == %{"error" => "ha_status"}
    end

    test "returns 403 forbidden when the role is guest", %{conn: conn} do
      blind = create_blind!()

      stub(RestClientMock, :call_service, fn _, _, _ ->
        flunk("HA service should not be invoked for guests")
      end)

      conn =
        conn
        |> authed("guest")
        |> post(~p"/api/blinds/#{blind.id}/position", %{position: 30})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end

    test "allows the resident role", %{conn: conn} do
      blind = create_blind!()

      expect(RestClientMock, :call_service, fn _, _, _ -> {:ok, []} end)

      conn =
        conn
        |> authed("resident")
        |> post(~p"/api/blinds/#{blind.id}/position", %{position: 30})

      assert conn.status == 204
    end
  end

  describe "POST /api/blinds/:id/open|close|stop" do
    setup do
      blind = create_blind!()
      %{blind: blind}
    end

    test "open issues cover.open_cover and returns 204", %{conn: conn, blind: blind} do
      expect(RestClientMock, :call_service, fn "cover", "open_cover", body ->
        assert body == %{"entity_id" => blind.ha_entity_id}
        {:ok, []}
      end)

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/open")

      assert conn.status == 204
    end

    test "close issues cover.close_cover and returns 204", %{conn: conn, blind: blind} do
      expect(RestClientMock, :call_service, fn "cover", "close_cover", body ->
        assert body == %{"entity_id" => blind.ha_entity_id}
        {:ok, []}
      end)

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/close")

      assert conn.status == 204
    end

    test "stop issues cover.stop_cover and returns 204", %{conn: conn, blind: blind} do
      expect(RestClientMock, :call_service, fn "cover", "stop_cover", body ->
        assert body == %{"entity_id" => blind.ha_entity_id}
        {:ok, []}
      end)

      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/#{blind.id}/stop")

      assert conn.status == 204
    end

    test "returns 403 forbidden when the role is guest", %{conn: conn, blind: blind} do
      stub(RestClientMock, :call_service, fn _, _, _ ->
        flunk("HA service should not be invoked for guests")
      end)

      conn =
        conn
        |> authed("guest")
        |> post(~p"/api/blinds/#{blind.id}/open")

      assert json_response(conn, 403) == %{"error" => "forbidden"}
    end

    test "returns 404 not_found for unknown blinds", %{conn: conn} do
      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/999999/close")

      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "returns 404 bad_id for unparseable ids", %{conn: conn} do
      conn =
        conn
        |> authed("admin")
        |> post(~p"/api/blinds/abc/stop")

      assert json_response(conn, 404) == %{"error" => "bad_id"}
    end
  end
end
