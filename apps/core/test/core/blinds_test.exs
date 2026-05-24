defmodule Core.BlindsTest do
  use ExUnit.Case, async: false

  alias Core.Blinds
  alias Core.Blinds.Blind
  alias Core.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
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

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
