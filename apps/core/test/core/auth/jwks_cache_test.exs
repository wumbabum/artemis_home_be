defmodule Core.Auth.JwksCacheTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Mox

  alias Core.Auth.JwksCache
  alias Core.Auth.JwksCache.HttpFetcherMock

  setup :set_mox_global
  setup :verify_on_exit!

  describe "fetch/2" do
    test "returns the key matching the requested kid after a cache miss" do
      keys = [
        %{"kid" => "k1", "kty" => "RSA", "n" => "n1", "e" => "AQAB"},
        %{"kid" => "k2", "kty" => "RSA", "n" => "n2", "e" => "AQAB"}
      ]

      stub(HttpFetcherMock, :fetch_jwks, fn _domain -> {:ok, %{"keys" => keys}} end)

      {:ok, pid} = JwksCache.start_link(domain: "test.auth0.com")

      assert {:ok, %{"kid" => "k1"}} = JwksCache.fetch("k1", pid)
    end

    test "returns :unknown_kid when the JWKS does not contain the requested kid" do
      stub(HttpFetcherMock, :fetch_jwks, fn _domain ->
        {:ok, %{"keys" => [%{"kid" => "other", "kty" => "RSA"}]}}
      end)

      {:ok, pid} = JwksCache.start_link(domain: "test.auth0.com")

      assert {:error, :unknown_kid} = JwksCache.fetch("missing", pid)
    end
  end

  describe "property: any well-formed JWKS produces N cacheable entries" do
    property "every kid in the JWKS is retrievable" do
      check all(
              kids <-
                uniq_list_of(string(:alphanumeric, min_length: 1, max_length: 8),
                  min_length: 1,
                  max_length: 5
                )
            ) do
        keys = Enum.map(kids, fn kid -> %{"kid" => kid, "kty" => "RSA"} end)

        stub(HttpFetcherMock, :fetch_jwks, fn _domain -> {:ok, %{"keys" => keys}} end)

        {:ok, pid} = JwksCache.start_link(domain: "test.auth0.com")

        for kid <- kids do
          assert {:ok, %{"kid" => ^kid}} = JwksCache.fetch(kid, pid)
        end
      end
    end
  end
end
