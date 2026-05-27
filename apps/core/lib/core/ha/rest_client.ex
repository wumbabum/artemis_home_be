defmodule Core.HA.RestClient do
  @moduledoc """
  Behaviour for talking to Home Assistant over its REST API.

  Implementations talk to the URL configured in `:core, :ha_base_url`
  using the long-lived access token in `:core, :ha_token`. The default
  implementation is `Core.HA.RestClient.HttpFetcher` (Req-backed).
  Tests swap in `Core.HA.RestClientMock` via the
  `:core, :ha_rest_client` application env.

  Higher layers (the state cache, the blinds controller) should reach
  HA through this behaviour rather than constructing HTTP requests
  directly. That isolates the HTTP boundary and keeps the rest of the
  stack mockable with Mox.

  ## Error shapes

    * `{:error, :ha_unreachable}` — transport failure (DNS, timeout,
      connection refused).
    * `{:error, {:ha_status, status, body}}` — HA returned a non-2xx
      status. `status` is the integer HTTP status; `body` is the
      decoded response body (often `%{"message" => "..."}` for 4xx).
  """

  @type entity_state() :: %{required(String.t()) => term()}

  @typedoc """
  One HA config entry as returned by `GET /api/config/config_entries/entry`.

  Useful fields the BE consumes (see
  `planning/home-assistant-api/integration-status.md`):

    * `"domain"` (string)        — integration name, e.g. `"zwave_js"`
    * `"entry_id"` (string)      — opaque ULID; needed for `zwave_js/*`
                                   WebSocket commands in a later milestone
    * `"state"` (string)         — `"loaded"` for healthy; other values
                                   include `"setup_error"`, `"setup_retry"`,
                                   `"not_loaded"`, `"failed_unload"`
    * `"reason"` (string | nil)  — human-readable error when not loaded
    * `"disabled_by"` (string | nil) — non-nil when explicitly disabled
    * `"title"` (string)         — HA UI label
  """
  @type config_entry() :: %{required(String.t()) => term()}

  @callback list_states() :: {:ok, [entity_state()]} | {:error, term()}

  @callback get_state(entity_id :: String.t()) ::
              {:ok, entity_state()} | {:error, term()}

  @callback call_service(domain :: String.t(), service :: String.t(), body :: map()) ::
              {:ok, [entity_state()] | map()} | {:error, term()}

  @doc """
  Lists HA config entries. When `domain` is a binary, the response is
  filtered server-side to entries for that integration. When `nil`,
  every entry is returned. HA returns HTTP 200 with `[]` (not 404)
  for an integration that isn't installed.
  """
  @callback list_config_entries(domain :: String.t() | nil) ::
              {:ok, [config_entry()]} | {:error, term()}
end
