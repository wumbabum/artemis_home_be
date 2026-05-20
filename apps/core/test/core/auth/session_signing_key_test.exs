defmodule Core.Auth.SessionSigningKeyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Core.Auth.SessionSigningKey

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "artemis_signing_key_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    original = Application.get_env(:core, :session_signing_key_dir)
    Application.put_env(:core, :session_signing_key_dir, tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)

      if is_nil(original) do
        Application.delete_env(:core, :session_signing_key_dir)
      else
        Application.put_env(:core, :session_signing_key_dir, original)
      end
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "signer!/0" do
    test "generates and persists an RS256 keypair on first call", %{tmp_dir: dir} do
      signer = SessionSigningKey.signer!()

      assert %Joken.Signer{alg: "RS256"} = signer
      assert File.exists?(Path.join(dir, "session_signing.pem"))
      assert File.exists?(Path.join(dir, "session_signing.pub.pem"))
    end

    test "writes the private key with mode 0600", %{tmp_dir: dir} do
      _ = SessionSigningKey.signer!()
      {:ok, %{mode: mode}} = File.stat(Path.join(dir, "session_signing.pem"))

      assert Bitwise.band(mode, 0o777) == 0o600
    end

    test "writes the public key with mode 0644", %{tmp_dir: dir} do
      _ = SessionSigningKey.signer!()
      {:ok, %{mode: mode}} = File.stat(Path.join(dir, "session_signing.pub.pem"))

      assert Bitwise.band(mode, 0o777) == 0o644
    end

    test "returns equivalent signers on subsequent calls" do
      signer1 = SessionSigningKey.signer!()
      signer2 = SessionSigningKey.signer!()

      assert signer1 == signer2
    end

    test "creates the key directory if it does not exist" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "artemis_missing_dir_#{System.unique_integer([:positive])}")

      Application.put_env(:core, :session_signing_key_dir, tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      refute File.exists?(tmp_dir)
      _ = SessionSigningKey.signer!()
      assert File.dir?(tmp_dir)
    end
  end

  describe "property" do
    property "N repeated calls all return the same signer" do
      check all(n <- integer(1..10)) do
        first = SessionSigningKey.signer!()

        for _ <- 1..n do
          assert SessionSigningKey.signer!() == first
        end
      end
    end
  end
end
