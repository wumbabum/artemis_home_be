defmodule Core.BlindsTest do
  use ExUnit.Case, async: false

  import Mox

  alias Core.Blinds
  alias Core.Blinds.Blind
  alias Core.Blinds.StateCache
  alias Core.HA.RestClientMock
  alias Core.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  # Start a StateCache under the default name so the control
  # functions' `schedule_refresh_after/1` cast reaches a live process.
  defp start_cache!(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, Core.Blinds.StateCache)
      |> Keyword.put_new(:poll_interval_ms, :manual)

    start_supervised!({StateCache, opts})
    :ok
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Left Window Blind",
        ha_entity_id: "cover.living_room_left",
        manufacturer: "SmartWings",
        protocol: "zwave",
        sort_order: 0
      },
      overrides
    )
  end

  describe "list_blinds/0" do
    test "returns blinds ordered by sort_order then id" do
      {:ok, b1} = Blinds.create_blind(valid_attrs(%{ha_entity_id: "cover.a", sort_order: 2}))
      {:ok, b2} = Blinds.create_blind(valid_attrs(%{ha_entity_id: "cover.b", sort_order: 1}))
      {:ok, b3} = Blinds.create_blind(valid_attrs(%{ha_entity_id: "cover.c", sort_order: 1}))

      assert [^b2, ^b3, ^b1] = Blinds.list_blinds()
    end

    test "returns an empty list when no blinds exist" do
      assert [] = Blinds.list_blinds()
    end
  end

  describe "get_blind!/1" do
    test "returns the blind when it exists" do
      {:ok, blind} = Blinds.create_blind(valid_attrs())

      assert ^blind = Blinds.get_blind!(blind.id)
    end

    test "raises Ecto.NoResultsError when the blind is missing" do
      assert_raise Ecto.NoResultsError, fn -> Blinds.get_blind!(-1) end
    end
  end

  describe "get_blind_by_ha_entity_id/1" do
    test "returns the blind when ha_entity_id matches" do
      {:ok, blind} = Blinds.create_blind(valid_attrs(%{ha_entity_id: "cover.foo"}))

      assert %Blind{id: id} = Blinds.get_blind_by_ha_entity_id("cover.foo")
      assert id == blind.id
    end

    test "returns nil when no row matches" do
      assert Blinds.get_blind_by_ha_entity_id("cover.missing") == nil
    end

    test "returns nil for non-binary input" do
      assert Blinds.get_blind_by_ha_entity_id(nil) == nil
      assert Blinds.get_blind_by_ha_entity_id(123) == nil
    end
  end

  describe "create_blind/1" do
    test "inserts a new blind with all fields" do
      assert {:ok, blind} = Blinds.create_blind(valid_attrs())

      assert blind.name == "Left Window Blind"
      assert blind.ha_entity_id == "cover.living_room_left"
      assert blind.manufacturer == "SmartWings"
      assert blind.protocol == "zwave"
      assert blind.sort_order == 0
    end

    test "defaults sort_order to 0 when omitted" do
      attrs = valid_attrs() |> Map.delete(:sort_order)

      assert {:ok, blind} = Blinds.create_blind(attrs)
      assert blind.sort_order == 0
    end

    test "returns {:error, changeset} when name is missing" do
      attrs = valid_attrs() |> Map.delete(:name)

      assert {:error, %Ecto.Changeset{} = changeset} = Blinds.create_blind(attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns {:error, changeset} when ha_entity_id is missing" do
      attrs = valid_attrs() |> Map.delete(:ha_entity_id)

      assert {:error, %Ecto.Changeset{} = changeset} = Blinds.create_blind(attrs)
      assert %{ha_entity_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns {:error, changeset} on duplicate ha_entity_id" do
      assert {:ok, _} = Blinds.create_blind(valid_attrs())

      assert {:error, %Ecto.Changeset{} = changeset} = Blinds.create_blind(valid_attrs())
      assert %{ha_entity_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_blind/2" do
    test "updates the writable fields and leaves the rest alone" do
      {:ok, blind} = Blinds.create_blind(valid_attrs())

      assert {:ok, updated} =
               Blinds.update_blind(blind, %{name: "Right Window Blind", sort_order: 5})

      assert updated.name == "Right Window Blind"
      assert updated.sort_order == 5
      assert updated.ha_entity_id == blind.ha_entity_id
    end

    test "returns {:error, changeset} when validation fails" do
      {:ok, blind} = Blinds.create_blind(valid_attrs())

      assert {:error, %Ecto.Changeset{} = changeset} =
               Blinds.update_blind(blind, %{name: ""})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_blind/1" do
    test "removes the row" do
      {:ok, blind} = Blinds.create_blind(valid_attrs())

      assert {:ok, _} = Blinds.delete_blind(blind)
      assert_raise Ecto.NoResultsError, fn -> Blinds.get_blind!(blind.id) end
    end
  end

  describe "open/1, close/1, stop/1" do
    setup do
      :ok = start_cache!()
      stub(RestClientMock, :list_states, fn -> {:ok, []} end)
      {:ok, blind} = Blinds.create_blind(valid_attrs())
      %{blind: blind}
    end

    test "open/1 issues cover.open_cover with the blind's entity id", %{blind: blind} do
      expect(RestClientMock, :call_service, fn "cover", "open_cover", body ->
        assert body == %{"entity_id" => blind.ha_entity_id}
        {:ok, []}
      end)

      assert :ok = Blinds.open(blind.id)
    end

    test "close/1 issues cover.close_cover with the blind's entity id", %{blind: blind} do
      expect(RestClientMock, :call_service, fn "cover", "close_cover", body ->
        assert body == %{"entity_id" => blind.ha_entity_id}
        {:ok, []}
      end)

      assert :ok = Blinds.close(blind.id)
    end

    test "stop/1 issues cover.stop_cover with the blind's entity id", %{blind: blind} do
      expect(RestClientMock, :call_service, fn "cover", "stop_cover", body ->
        assert body == %{"entity_id" => blind.ha_entity_id}
        {:ok, []}
      end)

      assert :ok = Blinds.stop(blind.id)
    end

    test "returns {:error, :not_found} when the blind doesn't exist" do
      assert {:error, :not_found} = Blinds.open(-1)
      assert {:error, :not_found} = Blinds.close(-1)
      assert {:error, :not_found} = Blinds.stop(-1)
    end

    test "propagates HA transport errors", %{blind: blind} do
      expect(RestClientMock, :call_service, fn _, _, _ -> {:error, :ha_unreachable} end)

      assert {:error, :ha_unreachable} = Blinds.open(blind.id)
    end

    test "propagates HA non-2xx status errors", %{blind: blind} do
      expect(RestClientMock, :call_service, fn _, _, _ ->
        {:error, {:ha_status, 503, %{"message" => "boom"}}}
      end)

      assert {:error, {:ha_status, 503, _}} = Blinds.close(blind.id)
    end
  end

  describe "set_position/2" do
    setup do
      :ok = start_cache!()
      stub(RestClientMock, :list_states, fn -> {:ok, []} end)
      {:ok, blind} = Blinds.create_blind(valid_attrs())
      %{blind: blind}
    end

    test "issues cover.set_cover_position with entity id + position", %{blind: blind} do
      expect(RestClientMock, :call_service, fn "cover", "set_cover_position", body ->
        assert body == %{"entity_id" => blind.ha_entity_id, "position" => 30}
        {:ok, []}
      end)

      assert :ok = Blinds.set_position(blind.id, 30)
    end

    test "accepts the integer boundary values 0 and 100", %{blind: blind} do
      expect(RestClientMock, :call_service, 2, fn _, _, %{"position" => p} ->
        assert p in [0, 100]
        {:ok, []}
      end)

      assert :ok = Blinds.set_position(blind.id, 0)
      assert :ok = Blinds.set_position(blind.id, 100)
    end

    test "returns :invalid_position for out-of-range integers", %{blind: blind} do
      assert {:error, :invalid_position} = Blinds.set_position(blind.id, -1)
      assert {:error, :invalid_position} = Blinds.set_position(blind.id, 101)
    end

    test "returns :invalid_position for non-integer positions", %{blind: blind} do
      assert {:error, :invalid_position} = Blinds.set_position(blind.id, 50.5)
      assert {:error, :invalid_position} = Blinds.set_position(blind.id, "50")
      assert {:error, :invalid_position} = Blinds.set_position(blind.id, nil)
    end

    test "does not call HA when the position is invalid", %{blind: blind} do
      stub(RestClientMock, :call_service, fn _, _, _ ->
        flunk("call_service should not be invoked when validation fails")
      end)

      assert {:error, :invalid_position} = Blinds.set_position(blind.id, 200)
    end

    test "returns :not_found when the blind doesn't exist" do
      assert {:error, :not_found} = Blinds.set_position(-1, 50)
    end

    test "propagates HA errors", %{blind: blind} do
      expect(RestClientMock, :call_service, fn _, _, _ -> {:error, :ha_unreachable} end)

      assert {:error, :ha_unreachable} = Blinds.set_position(blind.id, 50)
    end
  end

  describe "control functions trigger an adaptive cache refresh" do
    test "schedules a poll after a successful service call" do
      test_pid = self()

      # Use a non-default cache name to avoid colliding with any
      # already-running default cache, then point Core.Blinds at it
      # by starting it under the default name. The trick: we override
      # the cache name through the test's start_supervised! call.
      :ok = start_cache!()

      RestClientMock
      |> stub(:call_service, fn _, _, _ -> {:ok, []} end)
      |> stub(:list_states, fn ->
        send(test_pid, :polled)
        {:ok, []}
      end)

      {:ok, blind} = Blinds.create_blind(valid_attrs())

      assert :ok = Blinds.open(blind.id)

      # The control function schedules a refresh ~1s out. Allow ample
      # slack so the assertion isn't flaky on a busy CI host.
      assert_receive :polled, 3_000
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
