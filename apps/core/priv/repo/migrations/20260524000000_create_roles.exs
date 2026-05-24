defmodule Core.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles) do
      add :name, :string, null: false
      add :description, :string
      timestamps()
    end

    create unique_index(:roles, [:name])

    # Seed the three v0.1 roles in the same migration so they exist
    # after every `mix ecto.setup` / `mix ecto.reset`. Future role
    # changes (renames, splits) get their own migrations and edit
    # these rows in place rather than dropping and re-seeding.
    execute(
      """
      INSERT INTO roles (name, description, inserted_at, updated_at)
      VALUES
        ('admin',    'Full control over this home and its members.', NOW(), NOW()),
        ('resident', 'Can control devices and create schedules.',    NOW(), NOW()),
        ('guest',    'Limited time-bounded access via guest keys.',  NOW(), NOW())
      """,
      "DELETE FROM roles WHERE name IN ('admin', 'resident', 'guest')"
    )
  end
end
