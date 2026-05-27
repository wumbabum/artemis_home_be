defmodule Core.Home do
  @moduledoc """
  Home-level capability queries the FE drives off of.

  v0.1 exposes one operation: `integration_status/1`. Given an HA
  integration `domain` (e.g. `"zwave_js"`), the BE fetches the
  matching config entry from HA and normalizes it into a small map
  the FE can render directly (green light, error tooltip, hidden
  button, etc.).

  Future v0.2+ work will extend this module with companion
  capabilities (per-platform availability, hub metadata, radio
  health) without breaking the existing contract.

  ## Status mapping

  Maps `list_config_entries/1` results to `integration_status()`
  per the spec in
  `planning/home-assistant-api/integration-status.md`:

      []                                          -> available: false, reason: "not_installed"
      [entry] where disabled_by != nil            -> available: false, reason: "disabled_in_ha"
      [entry] where state == "loaded"             -> available: true,  reason: nil
      [entry] otherwise                           -> available: false, reason: entry["reason"] || entry["state"]

  When HA returns multiple entries for the same domain (rare —
  most integrations are singleton; Z-Wave allows multiple sticks),
  the first entry is used. Future work may surface the full list.

  HA transport / status errors are propagated unchanged so the
  controller can map them to HTTP 503.
  """

  alias Core.HA.RestClient

  @typedoc """
  Normalized integration-status payload the FE consumes.

    * `available`  — boolean, the FE's green-light signal.
    * `state`      — the raw HA state string when an entry exists
      (`"loaded"`, `"setup_error"`, `"setup_retry"`, etc.), `nil`
      when the integration isn't installed.
    * `reason`     — `nil` when available, otherwise a string the
      FE can show as a tooltip (`"not_installed"`,
      `"disabled_in_ha"`, or HA's verbatim `reason` / `state`).
    * `title`      — the HA UI label (e.g. `"Z-Wave JS"`), `nil`
      when no entry exists. Useful for the FE's "device hub: …"
      subtitle.
    * `entry_id`   — the HA config-entry ULID. Used by future
      `zwave_js/*` WebSocket commands; `nil` when no entry exists.
  """
  @type integration_status() :: %{
          available: boolean(),
          state: String.t() | nil,
          reason: String.t() | nil,
          title: String.t() | nil,
          entry_id: String.t() | nil
        }

  @doc """
  Fetches the status of the given HA integration domain.

  Returns `{:ok, integration_status()}` on any HA 2xx (including
  empty-list responses, which signal "not installed"). Returns
  `{:error, term()}` only on HA transport / non-2xx status errors.
  """
  @spec integration_status(String.t()) :: {:ok, integration_status()} | {:error, term()}
  def integration_status(domain) when is_binary(domain) do
    case ha_client().list_config_entries(domain) do
      {:ok, []} ->
        {:ok, not_installed()}

      {:ok, [entry | _]} ->
        {:ok, normalize(entry)}

      {:error, _reason} = error ->
        error
    end
  end

  defp not_installed do
    %{
      available: false,
      state: nil,
      reason: "not_installed",
      title: nil,
      entry_id: nil
    }
  end

  defp normalize(entry) do
    state = entry["state"]
    disabled_by = entry["disabled_by"]
    {available, reason} = availability(state, disabled_by, entry["reason"])

    %{
      available: available,
      state: state,
      reason: reason,
      title: entry["title"],
      entry_id: entry["entry_id"]
    }
  end

  defp availability(_state, disabled_by, _entry_reason) when not is_nil(disabled_by),
    do: {false, "disabled_in_ha"}

  defp availability("loaded", _disabled_by, _entry_reason), do: {true, nil}

  defp availability(state, _disabled_by, entry_reason),
    do: {false, entry_reason || state}

  defp ha_client do
    Application.get_env(:core, :ha_rest_client, RestClient.HttpFetcher)
  end
end
