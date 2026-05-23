defmodule Mix.Tasks.SeedHomes do
  @shortdoc "Seed homes into a user's Auth0 app_metadata.homes"

  @moduledoc """
  Writes one or more `{home_id, url}` entries to the specified user's
  `app_metadata.homes` via the Auth0 Management API.

  ## Usage

      mix seed.homes --user-sub "auth0|abc123" \\
        --home alpha:http://localhost:6565 \\
        --home beta:http://localhost:6566

  Calls `Core.Auth.register_home_for_user/3` once per `--home` argument.
  Each call is a read-modify-write against the Auth0 Management API so
  repeated invocations accumulate rather than overwrite.

  ## Required environment

  The same Auth0 Management API credentials used at runtime must be
  exported in the shell that invokes this task:

      AUTH0_DOMAIN
      AUTH0_M2M_CLIENT_ID
      AUTH0_M2M_CLIENT_SECRET

  `runtime.exs` reads these in `:dev` (the default `MIX_ENV` for `mix`
  invocations) via `System.get_env/1`.

  ## Option syntax

  - `--user-sub VALUE` (required, exactly one)
  - `--home id:url` (required, may repeat). The first `:` separates the
    home id from the url; subsequent `:` characters belong to the url
    (so URLs with ports work cleanly: `alpha:http://localhost:6565`).

  ## Exit behavior

  - Prints a one-line success message per home.
  - Continues past per-home errors so the rest still run, then exits
    non-zero (`Mix.raise/1`) if any home failed.
  - Invalid arguments exit immediately via `Mix.raise/1`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest, invalid} =
      OptionParser.parse(argv, strict: [user_sub: :string, home: :keep])

    if invalid != [] do
      Mix.raise("unrecognized options: #{inspect(invalid)}")
    end

    with {:ok, user_sub} <- fetch_user_sub(opts),
         {:ok, homes} <- parse_homes(opts) do
      failed = register_each(user_sub, homes)

      case failed do
        [] -> :ok
        _ -> Mix.raise("failed to register #{length(failed)} home(s)")
      end
    else
      {:error, msg} -> Mix.raise(msg)
    end
  end

  defp fetch_user_sub(opts) do
    case Keyword.get(opts, :user_sub) do
      sub when is_binary(sub) and sub != "" -> {:ok, sub}
      _ -> {:error, "missing --user-sub"}
    end
  end

  defp parse_homes(opts) do
    case Keyword.get_values(opts, :home) do
      [] ->
        {:error, "no --home arguments supplied"}

      raw ->
        parsed = Enum.map(raw, &parse_home/1)

        case Enum.find(parsed, &match?({:error, _}, &1)) do
          nil -> {:ok, Enum.map(parsed, fn {:ok, v} -> v end)}
          {:error, msg} -> {:error, msg}
        end
    end
  end

  defp parse_home(raw) do
    case String.split(raw, ":", parts: 2) do
      [home_id, url] when home_id != "" and url != "" ->
        {:ok, {home_id, url}}

      _ ->
        {:error, "invalid --home value, expected id:url, got: #{inspect(raw)}"}
    end
  end

  defp register_each(user_sub, homes) do
    Enum.reduce(homes, [], fn {home_id, url}, failed ->
      case Core.Auth.register_home_for_user(user_sub, home_id, url) do
        {:ok, _} ->
          Mix.shell().info("registered #{home_id} -> #{url}")
          failed

        {:error, reason} ->
          Mix.shell().error("failed to register #{home_id} -> #{url}: #{inspect(reason)}")
          [{home_id, url, reason} | failed]
      end
    end)
  end
end
