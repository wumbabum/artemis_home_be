defmodule Core.Auth.ManagementApiTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Mox

  alias Core.Auth.ManagementApi
  alias Core.Auth.ManagementApi.HttpClientMock

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    ManagementApi.clear_cache()
    on_exit(&ManagementApi.clear_cache/0)
    :ok
  end

  describe "update_app_metadata/2 happy path" do
    test "fetches an M2M token then patches the user's app_metadata" do
      test_pid = self()

      stub(HttpClientMock, :fetch_token, fn "test.auth0.com",
                                            "test_m2m_client_id",
                                            "test_m2m_client_secret" ->
        send(test_pid, :fetched_token)
        {:ok, %{access_token: "tok-1", expires_in: 86_400}}
      end)

      stub(HttpClientMock, :patch_user, fn "test.auth0.com", "tok-1", "auth0|user-1", body ->
        send(test_pid, {:patched, body})
        {:ok, %{"app_metadata" => %{"homes" => [%{"home_id" => "alpha"}]}}}
      end)

      patch = %{"homes" => [%{"home_id" => "alpha"}]}

      assert {:ok, %{"app_metadata" => %{"homes" => [%{"home_id" => "alpha"}]}}} =
               ManagementApi.update_app_metadata("auth0|user-1", patch)

      assert_received :fetched_token
      assert_received {:patched, %{"app_metadata" => ^patch}}
    end
  end

  describe "M2M token caching" do
    test "reuses the cached token when called twice within the cache window" do
      test_pid = self()

      stub(HttpClientMock, :fetch_token, fn _domain, _id, _secret ->
        send(test_pid, :fetched_token)
        {:ok, %{access_token: "tok-1", expires_in: 86_400}}
      end)

      stub(HttpClientMock, :patch_user, fn _domain, _token, _sub, _body ->
        {:ok, %{"ok" => true}}
      end)

      assert {:ok, _} = ManagementApi.update_app_metadata("auth0|user-1", %{"homes" => []})
      assert {:ok, _} = ManagementApi.update_app_metadata("auth0|user-2", %{"homes" => []})

      assert_received :fetched_token
      refute_received :fetched_token
    end

    test "refreshes the token when the cached one has expired" do
      test_pid = self()

      stub(HttpClientMock, :fetch_token, fn _domain, _id, _secret ->
        send(test_pid, :fetched_token)
        # expires_in: 2 => cache TTL = trunc(2 * 0.85) = 1 second
        {:ok, %{access_token: "tok-1", expires_in: 2}}
      end)

      stub(HttpClientMock, :patch_user, fn _domain, _token, _sub, _body ->
        {:ok, %{"ok" => true}}
      end)

      assert {:ok, _} = ManagementApi.update_app_metadata("auth0|user-1", %{})
      assert_received :fetched_token

      # Sleep past the cache window so the next call refreshes the token.
      Process.sleep(1_500)

      assert {:ok, _} = ManagementApi.update_app_metadata("auth0|user-1", %{})
      assert_received :fetched_token
    end
  end

  describe "error propagation" do
    test "propagates errors from the token endpoint" do
      stub(HttpClientMock, :fetch_token, fn _domain, _id, _secret ->
        {:error, :auth0_unreachable}
      end)

      assert {:error, :auth0_unreachable} =
               ManagementApi.update_app_metadata("auth0|user-1", %{})
    end

    test "propagates errors from the user PATCH endpoint" do
      stub(HttpClientMock, :fetch_token, fn _domain, _id, _secret ->
        {:ok, %{access_token: "tok-1", expires_in: 86_400}}
      end)

      stub(HttpClientMock, :patch_user, fn _domain, _token, _sub, _body ->
        {:error, {:http_status, 403, %{"error" => "Forbidden"}}}
      end)

      assert {:error, {:http_status, 403, %{"error" => "Forbidden"}}} =
               ManagementApi.update_app_metadata("auth0|user-1", %{})
    end
  end

  describe "missing configuration" do
    test "fails fast when auth0_domain is not configured" do
      stash_env(:auth0_domain)

      assert {:error, {:missing_config, :auth0_domain}} =
               ManagementApi.update_app_metadata("auth0|user-1", %{})
    end

    test "fails fast when the M2M client id is not configured" do
      stash_env(:auth0_m2m_client_id)

      assert {:error, {:missing_config, :auth0_m2m_client_id}} =
               ManagementApi.update_app_metadata("auth0|user-1", %{})
    end

    test "fails fast when the M2M client secret is not configured" do
      stash_env(:auth0_m2m_client_secret)

      assert {:error, {:missing_config, :auth0_m2m_client_secret}} =
               ManagementApi.update_app_metadata("auth0|user-1", %{})
    end
  end

  describe "property: any patch map round-trips through update_app_metadata" do
    property "the patch is wrapped in app_metadata and forwarded verbatim" do
      check all(
              patch <-
                map_of(
                  string(:alphanumeric, min_length: 1, max_length: 8),
                  one_of([
                    integer(),
                    string(:alphanumeric, max_length: 8),
                    boolean()
                  ]),
                  max_length: 4
                )
            ) do
        ManagementApi.clear_cache()
        test_pid = self()

        stub(HttpClientMock, :fetch_token, fn _domain, _id, _secret ->
          {:ok, %{access_token: "tok", expires_in: 3_600}}
        end)

        stub(HttpClientMock, :patch_user, fn _domain, _token, _sub, body ->
          send(test_pid, {:patched, body})
          {:ok, body}
        end)

        assert {:ok, _} = ManagementApi.update_app_metadata("auth0|user-1", patch)
        assert_received {:patched, %{"app_metadata" => ^patch}}
      end
    end
  end

  defp stash_env(key) do
    original = Application.get_env(:core, key)
    Application.delete_env(:core, key)
    on_exit(fn -> Application.put_env(:core, key, original) end)
  end
end
