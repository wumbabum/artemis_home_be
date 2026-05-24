defmodule Core.Accounts.RolesTest do
  use ExUnit.Case, async: false

  alias Core.Accounts.Role
  alias Core.Accounts.Roles
  alias Core.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "list_roles/0" do
    test "returns the three seeded roles in insertion order" do
      roles = Roles.list_roles()

      assert length(roles) == 3
      assert Enum.map(roles, & &1.name) == ["admin", "resident", "guest"]
      assert Enum.all?(roles, fn r -> is_binary(r.description) and r.description != "" end)
    end

    test "each role has a generated id and timestamps" do
      for role <- Roles.list_roles() do
        assert is_integer(role.id)
        assert role.id > 0
        assert %NaiveDateTime{} = role.inserted_at
        assert %NaiveDateTime{} = role.updated_at
      end
    end
  end

  describe "get_role!/1" do
    test "returns the role for a known id" do
      [first | _] = Roles.list_roles()

      assert %Role{id: id, name: name} = Roles.get_role!(first.id)
      assert id == first.id
      assert name == first.name
    end

    test "raises Ecto.NoResultsError for an unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Roles.get_role!(-1) end
    end
  end

  describe "get_role_by_name/1" do
    test "returns the role for each seeded name" do
      for name <- ~w(admin resident guest) do
        assert %Role{name: ^name} = Roles.get_role_by_name(name)
      end
    end

    test "returns nil for an unknown name" do
      assert is_nil(Roles.get_role_by_name("does_not_exist"))
    end
  end
end
