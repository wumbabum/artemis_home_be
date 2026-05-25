defmodule Core.Blinds.StateCache do
  @moduledoc """
  Caches Home Assistant cover-entity states in a process-public ETS
  table. Polls HA on a configurable cadence (default 5 s) using the
  configured `Core.HA.RestClient` implementation and writes each
  `cover.*` entity into the table keyed by `ha_entity_id`.

  Each entry is a map:

      %{
        ha_entity_id: String.t(),
        state: String.t() | nil,        # e.g. "open", "closed", "opening", "closing", "unavailable"
        position: 0..100 | nil,         # HA's `attributes.current_position`, nil when absent
        available: boolean(),           # state != "unavailable"
        last_polled_at: integer()       # monotonic seconds at the last successful poll for this entity
      }

  Reads (`get_state/2`, `get_all/1`) bypass the GenServer entirely and
  hit ETS directly. Writes are owned by the GenServer.

  ## Configuration

    * `:name` — GenServer + ETS table name. Defaults to
      `Core.Blinds.StateCache`. Use a unique name per test process to
      avoid collisions.
    * `:poll_interval_ms` — auto-poll cadence. Defaults to 5_000.
      Pass `:manual` (or 0) to disable auto-polling — tests use this
      and drive polls via `refresh_now/1`.
    * `:stale_after_ms` — duration after which an entry that has
      disappeared from HA's response is marked `available: false`.
      Defaults to 30_000.
    * `:ha_client` — module implementing `Core.HA.RestClient`.
      Defaults to `Application.get_env(:core, :ha_rest_client,
      Core.HA.RestClient.HttpFetcher)`.

  ## Group entities

  HA exposes a "cover group" entity (e.g. `cover.living_room_blinds`)
  alongside the underlying covers. Group entities carry a list-shaped
  `attributes.entity_id`; individual covers do not. The poll loop
  filters group entities out so the cache only ever contains
  individually-addressable covers.
  """

  use GenServer

  require Logger

  @default_name __MODULE__
  @default_poll_interval_ms 5_000
  @default_stale_after_ms 30_000

  ## Public API

  @doc """
  Starts the cache. See module doc for accepted options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Looks up one entry by HA entity id. Returns `{:ok, entry}` or
  `{:error, :not_cached}` when the entity has never been seen.
  """
  @spec get_state(String.t(), atom()) :: {:ok, map()} | {:error, :not_cached}
  def get_state(ha_entity_id, name \\ @default_name) when is_binary(ha_entity_id) do
    case safe_lookup(name, ha_entity_id) do
      [{^ha_entity_id, entry}] -> {:ok, entry}
      _ -> {:error, :not_cached}
    end
  end

  @doc """
  Returns every cached entry as a map keyed by `ha_entity_id`.
  """
  @spec get_all(atom()) :: %{String.t() => map()}
  def get_all(name \\ @default_name) do
    case safe_tab2list(name) do
      :no_table -> %{}
      entries -> Map.new(entries)
    end
  end

  @doc """
  Forces an immediate poll. Blocks until the poll completes (or the
  HA client returns an error). Returns `:ok` regardless of outcome —
  errors are logged, not raised.
  """
  @spec refresh_now(atom()) :: :ok
  def refresh_now(name \\ @default_name) do
    GenServer.call(name, :refresh)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, @default_name)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
    stale_after_ms = Keyword.get(opts, :stale_after_ms, @default_stale_after_ms)

    ha_client =
      Keyword.get_lazy(opts, :ha_client, fn ->
        Application.get_env(:core, :ha_rest_client, Core.HA.RestClient.HttpFetcher)
      end)

    :ets.new(name, [:set, :public, :named_table, read_concurrency: true])

    state = %{
      table: name,
      poll_interval_ms: normalize_interval(poll_interval_ms),
      stale_after_ms: stale_after_ms,
      ha_client: ha_client,
      timer_ref: nil
    }

    {:ok, schedule_next_poll(state)}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    new_state = state |> cancel_timer() |> do_poll() |> schedule_next_poll()
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:poll, state) do
    {:noreply, state |> do_poll() |> schedule_next_poll()}
  end

  ## Internal helpers

  defp do_poll(state) do
    case state.ha_client.list_states() do
      {:ok, states} when is_list(states) ->
        now = monotonic_seconds()
        seen = states |> Enum.filter(&cover_entity?/1) |> upsert_entries(state.table, now)
        mark_stale_entries(state.table, seen, now, div(state.stale_after_ms, 1000))
        state

      {:error, reason} ->
        Logger.warning("StateCache poll failed: #{inspect(reason)}")
        state
    end
  end

  defp cover_entity?(%{"entity_id" => entity_id} = entity) when is_binary(entity_id) do
    String.starts_with?(entity_id, "cover.") and not group_entity?(entity)
  end

  defp cover_entity?(_), do: false

  # HA cover-group entities carry a list-shaped `attributes.entity_id`
  # listing their members. Individual covers do not.
  defp group_entity?(%{"attributes" => %{"entity_id" => members}}) when is_list(members),
    do: true

  defp group_entity?(_), do: false

  defp upsert_entries(entities, table, now) do
    Enum.reduce(entities, MapSet.new(), fn entity, acc ->
      entry = build_entry(entity, now)
      :ets.insert(table, {entry.ha_entity_id, entry})
      MapSet.put(acc, entry.ha_entity_id)
    end)
  end

  defp build_entry(%{"entity_id" => ha_entity_id, "state" => state} = entity, now) do
    position = get_in(entity, ["attributes", "current_position"])

    %{
      ha_entity_id: ha_entity_id,
      state: state,
      position: position,
      available: state != "unavailable",
      last_polled_at: now
    }
  end

  defp mark_stale_entries(table, seen, now, stale_after_seconds) do
    threshold = now - stale_after_seconds

    table
    |> :ets.tab2list()
    |> Enum.each(fn {ha_entity_id, entry} ->
      cond do
        MapSet.member?(seen, ha_entity_id) ->
          :ok

        entry.last_polled_at <= threshold ->
          :ets.insert(table, {ha_entity_id, %{entry | available: false}})

        true ->
          :ok
      end
    end)

    :ok
  end

  defp schedule_next_poll(%{poll_interval_ms: :manual} = state), do: state

  defp schedule_next_poll(state) do
    timer_ref = Process.send_after(self(), :poll, state.poll_interval_ms)
    %{state | timer_ref: timer_ref}
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    _ = Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  defp normalize_interval(:manual), do: :manual
  defp normalize_interval(0), do: :manual
  defp normalize_interval(ms) when is_integer(ms) and ms > 0, do: ms

  defp monotonic_seconds, do: System.monotonic_time(:second)

  defp safe_lookup(name, key) do
    :ets.lookup(name, key)
  rescue
    ArgumentError -> []
  end

  defp safe_tab2list(name) do
    :ets.tab2list(name)
  rescue
    ArgumentError -> :no_table
  end
end
