defmodule Core.Accounts.UsersTest do
  use ExUnit.Case, async: false

  alias Core.Accounts.Roles
  alias Core.Accounts.User
  alias Core.Accounts.Users
  alias Core.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "upsert_from_auth0/1 — new user" do
    test "creates a new user with the guest role by default" do
      attrs = %{
        auth0_sub: "google-oauth2|new-user-1",
        email: "new@example.com",
        name: "New User",
        picture: "https://example.com/avatar.png"
      }

      assert {:ok, %User{} = user} = Users.upsert_from_auth0(attrs)
      assert user.auth0_sub == attrs.auth0_sub
      assert user.email == attrs.email
      assert user.name == attrs.name
      assert user.picture == attrs.picture
      assert user.role_id == Roles.get_role_by_name("guest").id
    end

    test "creates the first user with the admin role when SEED_ADMIN_AUTH0_SUB matches" do
      attrs = %{
        auth0_sub: Application.fetch_env!(:core, :seed_admin_auth0_sub),
        email: "admin@example.com",
        name: "Admin User"
      }

      assert {:ok, %User{} = user} = Users.upsert_from_auth0(attrs)
      assert user.role_id == Roles.get_role_by_name("admin").id
    end

    test "does NOT promote to admin when the table already has users, even if sub matches" do
      Users.upsert_from_auth0(%{
        auth0_sub: "google-oauth2|earlier-user",
        email: "earlier@example.com",
        name: "Earlier User"
      })

      attrs = %{
        auth0_sub: Application.fetch_env!(:core, :seed_admin_auth0_sub),
        email: "would-be-admin@example.com",
        name: "Late Bird"
      }

      assert {:ok, %User{} = user} = Users.upsert_from_auth0(attrs)
      assert user.role_id == Roles.get_role_by_name("guest").id
    end

    test "treats a nil or blank SEED_ADMIN_AUTH0_SUB config as no seed admin" do
      original = Application.get_env(:core, :seed_admin_auth0_sub)
      Application.put_env(:core, :seed_admin_auth0_sub, nil)
      on_exit(fn -> Application.put_env(:core, :seed_admin_auth0_sub, original) end)

      attrs = %{
        auth0_sub: "google-oauth2|whoever",
        email: "u@example.com",
        name: "U"
      }

      assert {:ok, %User{role_id: role_id}} = Users.upsert_from_auth0(attrs)
      assert role_id == Roles.get_role_by_name("guest").id
    end

    test "accepts string-keyed input from JWT claims" do
      attrs = %{
        "auth0_sub" => "google-oauth2|string-keys",
        "email" => "sk@example.com",
        "name" => "String Keys",
        "picture" => nil
      }

      assert {:ok, %User{auth0_sub: "google-oauth2|string-keys"}} =
               Users.upsert_from_auth0(attrs)
    end

    test "returns {:error, changeset} when required fields are missing" do
      attrs = %{auth0_sub: "google-oauth2|partial", email: "p@example.com"}

      assert {:error, %Ecto.Changeset{valid?: false}} = Users.upsert_from_auth0(attrs)
    end
  end

  describe "upsert_from_auth0/1 — existing user" do
    setup do
      attrs = %{
        auth0_sub: "google-oauth2|existing-user",
        email: "original@example.com",
        name: "Original Name",
        picture: nil
      }

      {:ok, user} = Users.upsert_from_auth0(attrs)
      %{user: user}
    end

    test "updates email, name, and picture", %{user: original} do
      attrs = %{
        auth0_sub: original.auth0_sub,
        email: "updated@example.com",
        name: "Updated Name",
        picture: "https://example.com/new.png"
      }

      assert {:ok, %User{} = updated} = Users.upsert_from_auth0(attrs)
      assert updated.id == original.id
      assert updated.email == "updated@example.com"
      assert updated.name == "Updated Name"
      assert updated.picture == "https://example.com/new.png"
    end

    test "preserves the existing role even if the user's seed status changes", %{
      user: original
    } do
      attrs = %{
        auth0_sub: original.auth0_sub,
        email: "renamed@example.com",
        name: "Same User Renamed"
      }

      {:ok, updated} = Users.upsert_from_auth0(attrs)
      assert updated.role_id == original.role_id
    end
  end

  describe "get_user_by_auth0_sub/1" do
    test "returns the user for a known auth0_sub" do
      attrs = %{
        auth0_sub: "google-oauth2|lookup-target",
        email: "l@example.com",
        name: "Lookup Target"
      }

      {:ok, _} = Users.upsert_from_auth0(attrs)

      assert %User{auth0_sub: "google-oauth2|lookup-target"} =
               Users.get_user_by_auth0_sub(attrs.auth0_sub)
    end

    test "returns nil for an unknown auth0_sub" do
      assert is_nil(Users.get_user_by_auth0_sub("google-oauth2|nope"))
    end

    test "returns nil for non-binary input" do
      assert is_nil(Users.get_user_by_auth0_sub(nil))
      assert is_nil(Users.get_user_by_auth0_sub(123))
    end
  end
end
