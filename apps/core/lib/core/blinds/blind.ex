defmodule Core.Blinds.Blind do
  @moduledoc """
  A blind (motorized window covering) controlled via a Home Assistant
  `cover.*` entity. v0.1's single-home model means there is no
  `home_id` column; every row belongs to this BE's home.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t() :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          ha_entity_id: String.t() | nil,
          manufacturer: String.t() | nil,
          protocol: String.t() | nil,
          sort_order: integer() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "blinds" do
    field(:name, :string)
    field(:ha_entity_id, :string)
    field(:manufacturer, :string)
    field(:protocol, :string)
    field(:sort_order, :integer, default: 0)
    timestamps()
  end

  @doc """
  Changeset for inserting or updating a blind. Required fields are
  `name` and `ha_entity_id`. `manufacturer` and `protocol` are
  optional metadata; `sort_order` defaults to 0.
  """
  @spec changeset(t() | Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(blind, attrs) do
    blind
    |> cast(attrs, [:name, :ha_entity_id, :manufacturer, :protocol, :sort_order])
    |> validate_required([:name, :ha_entity_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:ha_entity_id, min: 1, max: 255)
    |> validate_length(:manufacturer, max: 255)
    |> validate_length(:protocol, max: 255)
    |> unique_constraint(:ha_entity_id)
  end
end
