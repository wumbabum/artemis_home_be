defmodule Core.Auth.JwksCache do
  @moduledoc """
  Caches Auth0's JWKS keyed by `kid`. Fetches the JWKS document lazily on the
  first cache miss for a given `kid` and on every subsequent unknown `kid`.

  The default fetcher hits Auth0's JWKS endpoint via HTTP. Tests swap it for
  a Mox via `:core`'s `:jwks_fetcher` application env.
  """

  use GenServer

  @callback fetch(kid :: String.t()) :: {:ok, map()} | {:error, term()}

  @typep state :: %{cache: %{String.t() => map()}, domain: String.t() | nil}

  ## Public API

  @doc "Start a JwksCache. Pass `:domain` to override `Application.get_env(:core, :auth0_domain)` and `:name` for the GenServer name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Look up the JWKS entry for a given `kid`. Refreshes the cache on miss."
  @spec fetch(String.t(), GenServer.server()) :: {:ok, map()} | {:error, term()}
  def fetch(kid, server \\ __MODULE__) when is_binary(kid) do
    GenServer.call(server, {:fetch, kid})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    domain =
      Keyword.get_lazy(opts, :domain, fn ->
        Application.get_env(:core, :auth0_domain)
      end)

    {:ok, %{cache: %{}, domain: domain}}
  end

  @impl true
  def handle_call({:fetch, kid}, _from, state) do
    case Map.fetch(state.cache, kid) do
      {:ok, key} -> {:reply, {:ok, key}, state}
      :error -> refresh_and_lookup(kid, state)
    end
  end

  @spec refresh_and_lookup(String.t(), state()) ::
          {:reply, {:ok, map()} | {:error, term()}, state()}
  defp refresh_and_lookup(kid, state) do
    case fetcher().fetch_jwks(state.domain) do
      {:ok, %{"keys" => keys}} when is_list(keys) ->
        new_cache = Map.new(keys, fn %{"kid" => k} = key -> {k, key} end)

        case Map.fetch(new_cache, kid) do
          {:ok, key} -> {:reply, {:ok, key}, %{state | cache: new_cache}}
          :error -> {:reply, {:error, :unknown_kid}, %{state | cache: new_cache}}
        end

      {:ok, _other} ->
        {:reply, {:error, :malformed_jwks}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp fetcher do
    Application.get_env(:core, :jwks_fetcher, Core.Auth.JwksCache.HttpFetcher)
  end
end
