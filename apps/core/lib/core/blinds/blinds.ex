defmodule Core.Blinds do
  @moduledoc """
  Blinds context. Provides CRUD over the `blinds` table.

  Control functions (`open/1`, `close/1`, `stop/1`, `set_position/2`)
  that route through the Home Assistant REST client and the state
  cache land in a later commit; this module is data-access only.
  """

  import Ecto.Query, only: [from: 2]

  alias Core.Blinds.Blind
  alias Core.Repo

  @doc """
  Returns all blinds ordered by `sort_order` ascending, then `id`
  ascending as a stable tiebreaker for blinds with identical
  `sort_order` values (the default of 0).
  """
  @spec list_blinds() :: [Blind.t()]
  def list_blinds do
    Repo.all(from(b in Blind, order_by: [asc: b.sort_order, asc: b.id]))
  end

  @doc """
  Fetches a blind by primary key. Raises `Ecto.NoResultsError` when
  no row matches.
  """
  @spec get_blind!(integer() | String.t()) :: Blind.t()
  def get_blind!(id), do: Repo.get!(Blind, id)

  @doc """
  Looks up a blind by its Home Assistant entity id. Returns the
  `Blind` struct or `nil` if no row matches.
  """
  @spec get_blind_by_ha_entity_id(String.t() | nil) :: Blind.t() | nil
  def get_blind_by_ha_entity_id(ha_entity_id) when is_binary(ha_entity_id) do
    Repo.get_by(Blind, ha_entity_id: ha_entity_id)
  end

  def get_blind_by_ha_entity_id(_), do: nil

  @doc """
  Inserts a new blind from the given attribute map.
  """
  @spec create_blind(map()) :: {:ok, Blind.t()} | {:error, Ecto.Changeset.t()}
  def create_blind(attrs) when is_map(attrs) do
    %Blind{}
    |> Blind.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing blind with the given attribute map.
  """
  @spec update_blind(Blind.t(), map()) :: {:ok, Blind.t()} | {:error, Ecto.Changeset.t()}
  def update_blind(%Blind{} = blind, attrs) when is_map(attrs) do
    blind
    |> Blind.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes the given blind.
  """
  @spec delete_blind(Blind.t()) :: {:ok, Blind.t()} | {:error, Ecto.Changeset.t()}
  def delete_blind(%Blind{} = blind), do: Repo.delete(blind)
end
