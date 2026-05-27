defmodule Core.Accounts.Roles do
  @moduledoc """
  Read-only access to the seeded roles (`admin`, `resident`, `guest`).

  Roles are seeded by the `create_roles` migration. v0.1 does not allow
  creating, updating, or deleting roles at runtime; consumers look them
  up by id (from `users.role_id`) or by name (when assigning a default
  role during user upsert).
  """

  import Ecto.Query, only: [from: 2]

  alias Core.Accounts.Role
  alias Core.Repo

  @doc "Lists all roles in insertion order (admin, resident, guest)."
  @spec list_roles() :: [Role.t()]
  def list_roles do
    Repo.all(from(r in Role, order_by: r.id))
  end

  @doc """
  Fetches a role by primary key. Raises `Ecto.NoResultsError` if the
  id does not exist.
  """
  @spec get_role!(integer()) :: Role.t()
  def get_role!(id), do: Repo.get!(Role, id)

  @doc """
  Fetches a role by name. Returns `nil` if the name does not exist.
  """
  @spec get_role_by_name(String.t()) :: Role.t() | nil
  def get_role_by_name(name) when is_binary(name), do: Repo.get_by(Role, name: name)
end
