defmodule Core.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :auth0_sub, :string, null: false
      add :email, :string, null: false
      add :name, :string, null: false
      add :picture, :string
      add :role_id, references(:roles, on_delete: :restrict), null: false
      timestamps()
    end

    create unique_index(:users, [:auth0_sub])
    create index(:users, [:role_id])
  end
end
