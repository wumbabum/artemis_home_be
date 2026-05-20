defmodule Core.Auth.SessionToken do
  @moduledoc """
  Issues and verifies this BE's session JWTs.

  Signed with the RSA keypair returned by `Core.Auth.SessionSigningKey`.
  TTL defaults to one hour. Higher layers should mock this module via Mox
  rather than reaching into Joken directly.
  """

  alias Core.Auth.SessionSigningKey

  @callback issue(claims :: map()) :: {:ok, String.t()}
  @callback verify(token :: String.t()) :: {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

  # 1 hour
  @default_ttl_seconds 3600

  @impl true
  @spec issue(map()) :: {:ok, String.t()}
  def issue(claims) when is_map(claims) do
    now = System.system_time(:second)

    full_claims =
      claims
      |> Map.put_new("iat", now)
      |> Map.put_new("exp", now + @default_ttl_seconds)

    {:ok, token, _claims} = Joken.encode_and_sign(full_claims, SessionSigningKey.signer!())
    {:ok, token}
  end

  @impl true
  @spec verify(String.t()) :: {:ok, map()} | {:error, term()}
  def verify(token) when is_binary(token) do
    with {:ok, claims} <- Joken.verify(token, SessionSigningKey.signer!()),
         :ok <- validate_exp(claims) do
      {:ok, claims}
    end
  end

  defp validate_exp(%{"exp" => exp}) when is_integer(exp) do
    if exp > System.system_time(:second), do: :ok, else: {:error, :token_expired}
  end

  defp validate_exp(_claims), do: {:error, :missing_exp}
end
