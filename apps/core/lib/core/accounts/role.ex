defmodule Core.Accounts.Role do
  @moduledoc """
  A role assignment for a user on this BE's home. Roles are seeded by
  the migration that creates the table and are not user-editable in
  v0.1; the seed contains exactly `admin`, `resident`, and `guest`.

  Future milestones may add role-customization, at which point a
  changeset/2 lands here. Until then this schema is read-only.
  """

  use Ecto.Schema

  @type t() :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          description: String.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "roles" do
    field(:name, :string)
    field(:description, :string)
    timestamps()
  end
end
