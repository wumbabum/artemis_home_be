defmodule Core.HA.RestClient.HttpFetcher do
  @moduledoc """
  Default implementation of `Core.HA.RestClient`: a Req-backed HTTP
  fetcher against the Home Assistant REST API.

  Reads its base URL and bearer token from application env:

    * `:core, :ha_base_url` — fully qualified, including the `/api`
      suffix (e.g. `https://homeassistant.local:8123/api`).
    * `:core, :ha_token` — long-lived access token from HA.

  Exercised only via the SB-α smoke pause; excluded from coverage in
  `apps/core/coveralls.json` (HTTP boundary).
  """

  @behaviour Core.HA.RestClient

  @impl true
  def list_states do
    request(:get, "/states", nil)
  end

  @impl true
  def get_state(entity_id) when is_binary(entity_id) do
    request(:get, "/states/" <> URI.encode_www_form(entity_id), nil)
  end

  @impl true
  def call_service(domain, service, body)
      when is_binary(domain) and is_binary(service) and is_map(body) do
    request(:post, "/services/" <> domain <> "/" <> service, body)
  end

  @impl true
  def list_config_entries(domain) when is_binary(domain) or is_nil(domain) do
    query =
      case domain do
        nil -> ""
        d -> "?domain=" <> URI.encode_www_form(d)
      end

    request(:get, "/config/config_entries/entry" <> query, nil)
  end

  defp request(method, path, body) do
    with {:ok, base_url} <- fetch_config(:ha_base_url),
         {:ok, token} <- fetch_config(:ha_token) do
      url = base_url <> path
      headers = [{"authorization", "Bearer " <> token}]
      opts = [headers: headers] ++ method_opts(method, body)

      case Req.request([method: method, url: url] ++ opts) do
        {:ok, %{status: status, body: response_body}} when status in 200..299 ->
          {:ok, response_body}

        {:ok, %{status: status, body: response_body}} ->
          {:error, {:ha_status, status, response_body}}

        {:error, _reason} ->
          {:error, :ha_unreachable}
      end
    end
  end

  defp method_opts(:post, body) when is_map(body), do: [json: body]
  defp method_opts(_method, _body), do: []

  defp fetch_config(key) do
    case Application.get_env(:core, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_config, key}}
    end
  end
end
