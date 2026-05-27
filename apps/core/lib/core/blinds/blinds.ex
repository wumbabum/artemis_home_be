defmodule Core.Blinds do
  @moduledoc """
  Blinds context. Provides CRUD over the `blinds` table and the
  four write-side control operations (`open/1`, `close/1`,
  `stop/1`, `set_position/2`) that route through the Home
  Assistant REST client and queue an adaptive refresh on the
  `Core.Blinds.StateCache`.

  Each control function:

    1. Loads the blind row (or returns `{:error, :not_found}`).
    2. POSTs the corresponding cover service to HA via the
       configured `Core.HA.RestClient` implementation.
    3. On HA's 2xx, asks `StateCache.schedule_refresh_after/2` to
       run a poll within `@refresh_after_ms` and to open the
       cache's post-write fast-poll window. The cache keeps polling
       at the fast cadence (1 s by default) until the window
       expires (12 s by default), then returns to steady-state.
       The refresh is fire-and-forget; if the cache isn't running
       the cast is a no-op.

  HA's Z-Wave round-trip for SmartWings blinds is ~6–10 s, with
  superseding mid-flight writes stretching to ~12 s; the FE should
  surface a pending indicator until the cached `current_position`
  reflects the requested move.
  """

  import Ecto.Query, only: [from: 2]

  alias Core.Blinds.Blind
  alias Core.Blinds.StateCache
  alias Core.Repo

  # First post-write poll fires this many ms after the HA service
  # call returns. The StateCache then continues polling at its
  # fast cadence until its fast-poll window expires. See
  # planning/home-assistant-api/smart-blinds/ for the Z-Wave
  # latency profile.
  @refresh_after_ms 1_000

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

  @doc """
  Issues HA's `cover.open_cover` for the given blind.
  """
  @spec open(integer() | String.t()) :: :ok | {:error, term()}
  def open(blind_id), do: simple_service(blind_id, "open_cover")

  @doc """
  Issues HA's `cover.close_cover` for the given blind.
  """
  @spec close(integer() | String.t()) :: :ok | {:error, term()}
  def close(blind_id), do: simple_service(blind_id, "close_cover")

  @doc """
  Issues HA's `cover.stop_cover` for the given blind.
  """
  @spec stop(integer() | String.t()) :: :ok | {:error, term()}
  def stop(blind_id), do: simple_service(blind_id, "stop_cover")

  @doc """
  Issues HA's `cover.set_cover_position` for the given blind.

  `position` must be an integer in 0..100 (inclusive). Non-integer
  or out-of-range values return `{:error, :invalid_position}` and do
  not touch HA.
  """
  @spec set_position(integer() | String.t(), integer()) :: :ok | {:error, term()}
  def set_position(blind_id, position)
      when is_integer(position) and position >= 0 and position <= 100 do
    with_blind(blind_id, fn blind ->
      call_ha("cover", "set_cover_position", %{
        "entity_id" => blind.ha_entity_id,
        "position" => position
      })
    end)
  end

  def set_position(_blind_id, _position), do: {:error, :invalid_position}

  defp simple_service(blind_id, service) do
    with_blind(blind_id, fn blind ->
      call_ha("cover", service, %{"entity_id" => blind.ha_entity_id})
    end)
  end

  defp with_blind(blind_id, fun) do
    case Repo.get(Blind, blind_id) do
      nil -> {:error, :not_found}
      %Blind{} = blind -> fun.(blind)
    end
  end

  defp call_ha(domain, service, body) do
    case ha_client().call_service(domain, service, body) do
      {:ok, _response} ->
        :ok = StateCache.schedule_refresh_after(@refresh_after_ms)
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp ha_client do
    Application.get_env(:core, :ha_rest_client, Core.HA.RestClient.HttpFetcher)
  end
end
