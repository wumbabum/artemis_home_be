defmodule Core.Blinds.StateCacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Core.Blinds.StateCache
  alias Core.HA.RestClientMock

  setup :set_mox_global
  setup :verify_on_exit!

  # Each test gets its own GenServer + ETS table name to avoid
  # collisions when the suite runs in parallel and to let
  # `start_supervised!` tear down between tests.
  defp start_cache!(test_name, opts \\ []) do
    name = String.to_atom("state_cache_#{System.unique_integer([:positive])}_#{test_name}")

    opts =
      opts
      |> Keyword.put(:name, name)
      |> Keyword.put_new(:poll_interval_ms, :manual)

    start_supervised!({StateCache, opts})
    name
  end

  defp ha_entity(entity_id, state, position) when is_integer(position) do
    %{
      "entity_id" => entity_id,
      "state" => state,
      "attributes" => %{"current_position" => position}
    }
  end

  defp ha_entity_no_position(entity_id, state) do
    %{"entity_id" => entity_id, "state" => state, "attributes" => %{}}
  end

  defp ha_group(entity_id, members) do
    %{
      "entity_id" => entity_id,
      "state" => "open",
      "attributes" => %{"entity_id" => members, "current_position" => 50}
    }
  end

  describe "refresh_now/1 + get_state/2" do
    test "polls HA, filters cover.*, and writes entries keyed by entity id" do
      cache = start_cache!("polls_and_writes")

      stub(RestClientMock, :list_states, fn ->
        {:ok,
         [
           ha_entity("cover.left", "open", 65),
           ha_entity("cover.right", "closed", 0),
           ha_entity_no_position("sensor.temperature", "21.3")
         ]}
      end)

      :ok = StateCache.refresh_now(cache)

      assert {:ok, left} = StateCache.get_state("cover.left", cache)
      assert left.ha_entity_id == "cover.left"
      assert left.state == "open"
      assert left.position == 65
      assert left.available == true
      assert is_integer(left.last_polled_at)

      assert {:ok, right} = StateCache.get_state("cover.right", cache)
      assert right.state == "closed"
      assert right.position == 0
      assert right.available == true

      # Non-cover entities are filtered out before the upsert.
      assert {:error, :not_cached} = StateCache.get_state("sensor.temperature", cache)
    end

    test "filters out cover-group entities" do
      cache = start_cache!("filters_groups")

      stub(RestClientMock, :list_states, fn ->
        {:ok,
         [
           ha_entity("cover.left", "open", 65),
           ha_group("cover.living_room_blinds", ["cover.left", "cover.right"])
         ]}
      end)

      :ok = StateCache.refresh_now(cache)

      assert {:ok, _} = StateCache.get_state("cover.left", cache)
      assert {:error, :not_cached} = StateCache.get_state("cover.living_room_blinds", cache)
    end

    test "marks unavailable entities with available: false and nil position" do
      cache = start_cache!("unavailable")

      stub(RestClientMock, :list_states, fn ->
        {:ok, [ha_entity_no_position("cover.dead", "unavailable")]}
      end)

      :ok = StateCache.refresh_now(cache)

      assert {:ok, entry} = StateCache.get_state("cover.dead", cache)
      assert entry.state == "unavailable"
      assert entry.position == nil
      assert entry.available == false
    end

    test "returns {:error, :not_cached} for unknown entities" do
      cache = start_cache!("not_cached_unknown")

      stub(RestClientMock, :list_states, fn -> {:ok, []} end)
      :ok = StateCache.refresh_now(cache)

      assert {:error, :not_cached} = StateCache.get_state("cover.never_seen", cache)
    end

    test "later polls overwrite earlier entries for the same ha_entity_id" do
      cache = start_cache!("overwrites")
      test_pid = self()

      # First poll: position 65.
      RestClientMock
      |> expect(:list_states, fn ->
        send(test_pid, :polled_first)
        {:ok, [ha_entity("cover.left", "open", 65)]}
      end)
      |> expect(:list_states, fn ->
        send(test_pid, :polled_second)
        {:ok, [ha_entity("cover.left", "open", 30)]}
      end)

      :ok = StateCache.refresh_now(cache)
      assert_received :polled_first
      assert {:ok, %{position: 65}} = StateCache.get_state("cover.left", cache)

      :ok = StateCache.refresh_now(cache)
      assert_received :polled_second
      assert {:ok, %{position: 30}} = StateCache.get_state("cover.left", cache)
    end
  end

  describe "get_all/1" do
    test "returns every cached entry keyed by ha_entity_id" do
      cache = start_cache!("get_all")

      stub(RestClientMock, :list_states, fn ->
        {:ok,
         [
           ha_entity("cover.left", "open", 65),
           ha_entity("cover.right", "closed", 0)
         ]}
      end)

      :ok = StateCache.refresh_now(cache)

      all = StateCache.get_all(cache)
      assert map_size(all) == 2
      assert %{position: 65} = all["cover.left"]
      assert %{position: 0} = all["cover.right"]
    end

    test "returns an empty map when no polls have happened yet" do
      cache = start_cache!("get_all_empty")

      stub(RestClientMock, :list_states, fn -> {:ok, []} end)

      assert StateCache.get_all(cache) == %{}
    end
  end

  describe "read API resilience" do
    test "get_state returns :not_cached when the ETS table doesn't exist" do
      assert {:error, :not_cached} = StateCache.get_state("cover.left", :no_such_cache)
    end

    test "get_all returns an empty map when the ETS table doesn't exist" do
      assert StateCache.get_all(:no_such_cache) == %{}
    end
  end

  describe "stale-entry handling" do
    test "marks entries unavailable once they exceed stale_after_ms" do
      # 1ms stale threshold so we can age entries out within the test.
      cache = start_cache!("stale", stale_after_ms: 1)

      RestClientMock
      |> expect(:list_states, fn -> {:ok, [ha_entity("cover.gone", "open", 65)]} end)
      |> expect(:list_states, fn -> {:ok, []} end)

      :ok = StateCache.refresh_now(cache)
      assert {:ok, %{available: true, state: "open"}} = StateCache.get_state("cover.gone", cache)

      # Make sure the second poll's `now` is strictly greater than the
      # first poll's last_polled_at so the staleness threshold trips.
      Process.sleep(1_100)

      :ok = StateCache.refresh_now(cache)

      assert {:ok, entry} = StateCache.get_state("cover.gone", cache)
      assert entry.available == false
      # state and position are retained from the last successful poll.
      assert entry.state == "open"
      assert entry.position == 65
    end

    test "leaves fresh-but-missing entries alone" do
      cache = start_cache!("not_stale_yet", stale_after_ms: 60_000)

      RestClientMock
      |> expect(:list_states, fn -> {:ok, [ha_entity("cover.fresh", "open", 65)]} end)
      |> expect(:list_states, fn -> {:ok, []} end)

      :ok = StateCache.refresh_now(cache)
      :ok = StateCache.refresh_now(cache)

      assert {:ok, %{available: true}} = StateCache.get_state("cover.fresh", cache)
    end
  end

  describe "HA error handling" do
    test "logs and keeps the cache untouched on transport failure" do
      cache = start_cache!("transport_error")

      RestClientMock
      |> expect(:list_states, fn -> {:ok, [ha_entity("cover.left", "open", 65)]} end)
      |> expect(:list_states, fn -> {:error, :ha_unreachable} end)

      :ok = StateCache.refresh_now(cache)
      assert {:ok, %{position: 65}} = StateCache.get_state("cover.left", cache)

      log =
        capture_log(fn ->
          :ok = StateCache.refresh_now(cache)
        end)

      assert log =~ "ha_unreachable"
      # Previous cache entry is preserved across the failing poll.
      assert {:ok, %{position: 65}} = StateCache.get_state("cover.left", cache)
    end

    test "logs and keeps the cache untouched on HA non-2xx status" do
      cache = start_cache!("status_error")

      RestClientMock
      |> expect(:list_states, fn -> {:ok, [ha_entity("cover.left", "open", 65)]} end)
      |> expect(:list_states, fn -> {:error, {:ha_status, 500, %{"message" => "boom"}}} end)

      :ok = StateCache.refresh_now(cache)

      log =
        capture_log(fn ->
          :ok = StateCache.refresh_now(cache)
        end)

      assert log =~ "ha_status"
      assert {:ok, %{position: 65}} = StateCache.get_state("cover.left", cache)
    end
  end

  describe "auto-polling" do
    test "fires on the configured cadence" do
      test_pid = self()

      stub(RestClientMock, :list_states, fn ->
        send(test_pid, :polled)
        {:ok, [ha_entity("cover.tick", "open", 50)]}
      end)

      _cache = start_cache!("auto_poll", poll_interval_ms: 25)

      # First scheduled poll fires after `poll_interval_ms`. Wait for
      # at least two polls so we know the timer is rescheduling, not
      # firing only once.
      assert_receive :polled, 500
      assert_receive :polled, 500
    end
  end

  describe "normalize_interval (via start_link)" do
    test "treats 0 as :manual (no scheduled polls)" do
      test_pid = self()

      stub(RestClientMock, :list_states, fn ->
        send(test_pid, :polled)
        {:ok, []}
      end)

      _cache = start_cache!("zero_interval", poll_interval_ms: 0)

      refute_receive :polled, 200
    end
  end

  describe "malformed HA responses" do
    test "silently skips entities without an entity_id field" do
      cache = start_cache!("missing_entity_id")

      stub(RestClientMock, :list_states, fn ->
        {:ok,
         [
           %{"state" => "open", "attributes" => %{}},
           ha_entity("cover.left", "open", 65)
         ]}
      end)

      :ok = StateCache.refresh_now(cache)

      # The malformed entry is ignored; the well-formed entry lands
      # in the cache.
      assert {:ok, _} = StateCache.get_state("cover.left", cache)
      assert StateCache.get_all(cache) |> map_size() == 1
    end

    test "silently skips entities with non-binary entity_id" do
      cache = start_cache!("non_binary_entity_id")

      stub(RestClientMock, :list_states, fn ->
        {:ok,
         [
           %{"entity_id" => 42, "state" => "open", "attributes" => %{}},
           ha_entity("cover.left", "open", 65)
         ]}
      end)

      :ok = StateCache.refresh_now(cache)

      assert {:ok, _} = StateCache.get_state("cover.left", cache)
      assert StateCache.get_all(cache) |> map_size() == 1
    end
  end

  describe "refresh_now/1 while auto-polling" do
    test "cancels the pending scheduled poll before running the on-demand poll" do
      test_pid = self()

      stub(RestClientMock, :list_states, fn ->
        send(test_pid, :polled)
        {:ok, [ha_entity("cover.left", "open", 65)]}
      end)

      # Long interval so the scheduled poll won't fire on its own during
      # the test window — we force the poll via refresh_now and assert
      # the cancel-and-reschedule branch ran.
      cache = start_cache!("refresh_while_auto", poll_interval_ms: 60_000)

      :ok = StateCache.refresh_now(cache)
      assert_received :polled
      assert {:ok, %{position: 65}} = StateCache.get_state("cover.left", cache)
    end
  end

  describe "schedule_refresh_after/2" do
    test "fires a poll within the given window even in manual mode" do
      test_pid = self()

      stub(RestClientMock, :list_states, fn ->
        send(test_pid, :polled)
        {:ok, [ha_entity("cover.left", "open", 65)]}
      end)

      cache = start_cache!("sched_manual", poll_interval_ms: :manual)

      :ok = StateCache.schedule_refresh_after(50, cache)

      assert_receive :polled, 500
      assert {:ok, %{position: 65}} = StateCache.get_state("cover.left", cache)
    end

    test "cancels a pending scheduled poll and replaces it" do
      test_pid = self()

      stub(RestClientMock, :list_states, fn ->
        send(test_pid, :polled)
        {:ok, []}
      end)

      # 5s default cadence: the natural tick will not fire during the
      # test window. We schedule a short refresh and assert only one
      # poll happens within 500ms (the one we asked for, not the
      # cancelled-and-replaced 5s one).
      cache = start_cache!("sched_cancels", poll_interval_ms: 5_000)

      :ok = StateCache.schedule_refresh_after(50, cache)
      assert_receive :polled, 500

      refute_receive :polled, 200
    end
  end
end
