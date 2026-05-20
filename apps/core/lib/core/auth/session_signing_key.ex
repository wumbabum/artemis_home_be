defmodule Core.Auth.SessionSigningKey do
  @moduledoc """
  Loads (or generates on first use) the RSA-2048 keypair this BE uses to sign
  and verify its session JWTs.

  The private key is persisted at `<key_dir>/session_signing.pem` with mode
  0600. The public half lives next to it as `.pub.pem`. Both files must
  survive container restarts via a host-mounted volume \u2014 otherwise every
  session JWT issued before a restart becomes invalid.

  `key_dir` defaults to `Application.app_dir(:core, "priv/keys")`; tests
  override it via the `:session_signing_key_dir` application env.
  """

  @doc "Returns a `Joken.Signer` ready to sign and verify session JWTs."
  @spec signer!() :: Joken.Signer.t()
  def signer! do
    ensure_keypair!()
    Joken.Signer.create("RS256", %{"pem" => File.read!(private_pem_path())})
  end

  defp ensure_keypair! do
    unless File.exists?(private_pem_path()) do
      generate_and_write!()
    end

    :ok
  end

  defp generate_and_write! do
    File.mkdir_p!(key_dir())

    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_, private_pem} = JOSE.JWK.to_pem(jwk)
    {_, public_pem} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()

    File.write!(private_pem_path(), private_pem)
    File.write!(public_pem_path(), public_pem)
    File.chmod!(private_pem_path(), 0o600)
    File.chmod!(public_pem_path(), 0o644)
    :ok
  end

  defp key_dir do
    Application.get_env(
      :core,
      :session_signing_key_dir,
      Application.app_dir(:core, "priv/keys")
    )
  end

  defp private_pem_path, do: Path.join(key_dir(), "session_signing.pem")
  defp public_pem_path, do: Path.join(key_dir(), "session_signing.pub.pem")
end
