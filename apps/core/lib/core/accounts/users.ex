defmodule Core.Accounts.Users do
  @moduledoc """
  User context. Responsible for upserting users from verified Auth0
  claims and looking them up by their Auth0 subject identifier.

  Role assignment for new users:

  1. If the `users` table is empty AND the incoming `auth0_sub`
     matches the `SEED_ADMIN_AUTH0_SUB` env var (read into
     `:core, :seed_admin_auth0_sub` at boot), the user is created
     with the `admin` role.
  2. Otherwise the new user gets the `guest` role.

  Existing users keep their role on subsequent upserts — only
  profile fields (`email`, `name`, `picture`) are updated.
  """

  import Ecto.Query, only: [from: 2]

  alias Core.Accounts.Role
  alias Core.Accounts.User
  alias Core.Repo

  @doc """
  Upserts a user from a map of verified Auth0 claims. Accepts both
  string-keyed and atom-keyed inputs.

  Required keys: `auth0_sub`, `email`, `name`. Optional: `picture`.

  Returns `{:ok, user}` on success or `{:error, changeset}` on
  validation failure.
  """
  @spec upsert_from_auth0(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def upsert_from_auth0(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    result =
      case get_user_by_auth0_sub(attrs[:auth0_sub]) do
        nil ->
          attrs
          |> Map.put(:role_id, determine_role_id_for_new_user(attrs[:auth0_sub]))
          |> create_user()

        %User{} = user ->
          update_user_profile(user, attrs)
      end

    case result do
      {:ok, user} -> {:ok, Repo.preload(user, :role)}
      error -> error
    end
  end

  @doc """
  Looks up a user by their Auth0 subject identifier. Returns the
  `User` struct (with `:role` not preloaded) or `nil`.
  """
  @spec get_user_by_auth0_sub(String.t() | nil) :: User.t() | nil
  def get_user_by_auth0_sub(sub) when is_binary(sub) do
    Repo.get_by(User, auth0_sub: sub)
  end

  def get_user_by_auth0_sub(_), do: nil

  defp normalize_attrs(attrs) do
    attrs
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
    |> Map.new()
    |> Map.take([:auth0_sub, :email, :name, :picture])
  end

  defp create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  defp update_user_profile(user, attrs) do
    user
    |> User.changeset(Map.take(attrs, [:email, :name, :picture]))
    |> Repo.update()
  end

  defp determine_role_id_for_new_user(sub) do
    role_name = role_name_for_new_user(sub)

    Repo.one!(from(r in Role, where: r.name == ^role_name, select: r.id))
  end

  defp role_name_for_new_user(sub) do
    if no_users_yet?() and matches_seed_admin?(sub), do: "admin", else: "guest"
  end

  defp no_users_yet?, do: Repo.aggregate(User, :count) == 0

  defp matches_seed_admin?(sub) do
    case Application.get_env(:core, :seed_admin_auth0_sub) do
      seed when is_binary(seed) and seed != "" -> seed == sub
      _ -> false
    end
  end
end
