defmodule Web.Plugs.RequireRoleTest do
  use Web.ConnCase, async: false

  alias Web.Plugs.RequireRole

  describe "init/1" do
    test "returns the opts unchanged when :allowed is a non-empty list of strings" do
      opts = [allowed: ~w(admin resident)]
      assert RequireRole.init(opts) == opts
    end

    test "raises when :allowed is missing" do
      assert_raise ArgumentError, ~r/requires an :allowed/, fn ->
        RequireRole.init([])
      end
    end

    test "raises when :allowed is an empty list" do
      assert_raise ArgumentError, ~r/requires an :allowed/, fn ->
        RequireRole.init(allowed: [])
      end
    end

    test "raises when :allowed is not a list" do
      assert_raise ArgumentError, ~r/requires an :allowed/, fn ->
        RequireRole.init(allowed: "admin")
      end
    end

    test "raises when :allowed contains non-string entries" do
      assert_raise ArgumentError, ~r/role-name strings/, fn ->
        RequireRole.init(allowed: [:admin, "resident"])
      end
    end
  end

  describe "call/2" do
    setup do
      %{opts: RequireRole.init(allowed: ~w(admin resident))}
    end

    test "passes the conn through when the role is in the allow-list",
         %{conn: conn, opts: opts} do
      conn =
        conn
        |> Plug.Conn.assign(:current_user, %{user_sub: "abc", home_id: "alpha", role: "admin"})
        |> RequireRole.call(opts)

      refute conn.halted
    end

    test "returns 403 when the role is not in the allow-list",
         %{conn: conn, opts: opts} do
      conn =
        conn
        |> Plug.Conn.assign(:current_user, %{user_sub: "abc", home_id: "alpha", role: "guest"})
        |> RequireRole.call(opts)

      assert_forbidden(conn)
    end

    test "returns 403 when :current_user is missing", %{conn: conn, opts: opts} do
      conn = RequireRole.call(conn, opts)
      assert_forbidden(conn)
    end

    test "returns 403 when :current_user has no :role key", %{conn: conn, opts: opts} do
      conn =
        conn
        |> Plug.Conn.assign(:current_user, %{user_sub: "abc", home_id: "alpha"})
        |> RequireRole.call(opts)

      assert_forbidden(conn)
    end

    test "returns 403 when :role is not a binary", %{conn: conn, opts: opts} do
      conn =
        conn
        |> Plug.Conn.assign(:current_user, %{user_sub: "abc", home_id: "alpha", role: :admin})
        |> RequireRole.call(opts)

      assert_forbidden(conn)
    end
  end

  defp assert_forbidden(conn) do
    assert conn.halted
    assert conn.status == 403
    assert Jason.decode!(conn.resp_body) == %{"error" => "forbidden"}
  end
end
