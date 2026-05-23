defmodule Core.Auth.ManagementApi.HttpClient do
  @moduledoc """
  Default HTTP transport for the Auth0 Management API.

  Two operations are exposed:

    * `fetch_token/3` — performs the client_credentials grant against
      `https://<domain>/oauth/token` to obtain an M2M access token.
    * `patch_user/4` — PATCHes `https://<domain>/api/v2/users/:user_sub`
      with the supplied JSON body.

  Tests swap this implementation for a Mox via `:core`'s
  `:management_api_http_client` application env.
  """

  @callback fetch_token(
              domain :: String.t(),
              client_id :: String.t(),
              client_secret :: String.t()
            ) ::
              {:ok, %{access_token: String.t(), expires_in: pos_integer()}}
              | {:error, term()}

  @callback patch_user(
              domain :: String.t(),
              token :: String.t(),
              user_sub :: String.t(),
              body :: map()
            ) :: {:ok, map()} | {:error, term()}

  @callback get_user(
              domain :: String.t(),
              token :: String.t(),
              user_sub :: String.t()
            ) :: {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def fetch_token(domain, client_id, client_secret)
      when is_binary(domain) and is_binary(client_id) and is_binary(client_secret) do
    audience = "https://" <> domain <> "/api/v2/"
    url = "https://" <> domain <> "/oauth/token"

    body = %{
      "grant_type" => "client_credentials",
      "client_id" => client_id,
      "client_secret" => client_secret,
      "audience" => audience
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}}
      when is_binary(token) and is_integer(expires_in) ->
        {:ok, %{access_token: token, expires_in: expires_in}}

      {:ok, %{status: 200, body: _malformed}} ->
        {:error, :malformed_token_response}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:http_status, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def patch_user(domain, token, user_sub, body)
      when is_binary(domain) and is_binary(token) and is_binary(user_sub) and is_map(body) do
    url = user_url(domain, user_sub)
    headers = [{"authorization", "Bearer " <> token}]

    case Req.patch(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:http_status, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_user(domain, token, user_sub)
      when is_binary(domain) and is_binary(token) and is_binary(user_sub) do
    url = user_url(domain, user_sub)
    headers = [{"authorization", "Bearer " <> token}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: response_body}} when is_map(response_body) ->
        {:ok, response_body}

      {:ok, %{status: 200, body: _malformed}} ->
        {:error, :malformed_user_response}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:http_status, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp user_url(domain, user_sub) do
    "https://" <> domain <> "/api/v2/users/" <> URI.encode_www_form(user_sub)
  end
end
