defmodule Core.Repo.Migrations.CreateBlinds do
  use Ecto.Migration

  def change do
    create table(:blinds) do
      add(:name, :string, null: false)
      add(:ha_entity_id, :string, null: false)
      add(:manufacturer, :string)
      add(:protocol, :string)
      add(:sort_order, :integer, null: false, default: 0)
      timestamps()
    end

    create(unique_index(:blinds, [:ha_entity_id]))
  end
end
