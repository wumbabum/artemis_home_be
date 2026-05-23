defmodule Web.CorsTest do
  use Web.ConnCase, async: false

  alias Web.Cors

  describe "origins/1" do
    test "returns the configured allow-list" do
      original = Application.get_env(:web, :cors_allowed_origins)

      Application.put_env(:web, :cors_allowed_origins, [
        "http://localhost:6587",
        "https://artemis-home.fly.dev"
      ])

      on_exit(fn -> Application.put_env(:web, :cors_allowed_origins, original) end)

      assert Cors.origins(Phoenix.ConnTest.build_conn()) == [
               "http://localhost:6587",
               "https://artemis-home.fly.dev"
             ]
    end

    test "raises when :cors_allowed_origins is missing from app env" do
      original = Application.get_env(:web, :cors_allowed_origins)
      Application.delete_env(:web, :cors_allowed_origins)
      on_exit(fn -> Application.put_env(:web, :cors_allowed_origins, original) end)

      assert_raise ArgumentError, fn -> Cors.origins(Phoenix.ConnTest.build_conn()) end
    end
  end

  describe "preflight via the endpoint" do
    test "OPTIONS from an allowed origin returns the CORS allow headers", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:6587")
        |> put_req_header("access-control-request-method", "POST")
        |> options("/api/sessions")

      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:6587"]

      assert get_resp_header(conn, "access-control-allow-methods") |> List.first() =~ "POST"
    end

    test "OPTIONS from a disallowed origin does not echo that origin back", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://evil.example.com")
        |> put_req_header("access-control-request-method", "POST")
        |> options("/api/sessions")

      refute "http://evil.example.com" in get_resp_header(conn, "access-control-allow-origin")
    end

    test "responds even when the target route does not exist (preflight short-circuit)", %{
      conn: conn
    } do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:6587")
        |> put_req_header("access-control-request-method", "POST")
        |> options("/api/nonexistent/route")

      # CORS should answer the preflight regardless of route existence; the
      # router never gets a chance to 404 for OPTIONS.
      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:6587"]
    end
  end
end
