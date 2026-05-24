defmodule Core.Accounts.User do
  @moduledoc """
  A user authenticated via Auth0. Every row in this table is implicitly
  a member of this BE's home; v0.1's single-home model means there is
  no `home_memberships` table.

  Identified by `auth0_sub` (e.g. `"google-oauth2|117394610565503842179"`).
  Role is carried directly via `role_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Core.Accounts.Role

  @type t() :: %__MODULE__{
          id: integer() | nil,
          auth0_sub: String.t() | nil,
          email: String.t() | nil,
          name: String.t() | nil,
          picture: String.t() | nil,
          role_id: integer() | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field(:auth0_sub, :string)
    field(:email, :string)
    field(:name, :string)
    field(:picture, :string)
    belongs_to(:role, Role)
    timestamps()
  end

  @doc """
  Changeset for inserting or updating a user. Required fields are
  `auth0_sub`, `email`, `name`, `role_id`. `picture` is optional and
  defaults to nil.

  When updating an existing user, the caller should omit `auth0_sub`
  and `role_id` from `attrs` so they keep their existing values.
  """
  @spec changeset(t() | Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:auth0_sub, :email, :name, :picture, :role_id])
    |> validate_required([:auth0_sub, :email, :name, :role_id])
    |> validate_length(:auth0_sub, min: 1, max: 255)
    |> validate_length(:email, min: 3, max: 255)
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:auth0_sub)
    |> foreign_key_constraint(:role_id)
  end
end
