defmodule Mix.Tasks.SeedBlinds do
  @shortdoc "Seed blinds into the local Postgres database"

  @moduledoc """
  Creates (or updates) rows in the `blinds` table for each
  `--blind <ha_entity_id>:<name>` argument supplied on the command
  line.

  ## Usage

      mix seed.blinds \\
        --blind cover.living_room_tv_right_outbound_bottom:Right \\
        --blind cover.living_room_tv_left_outbound_bottom:Left

  Optional flags (apply to every `--blind` in the invocation):

      --manufacturer SmartWings    (default: SmartWings)
      --protocol     zwave         (default: zwave)

  ## Idempotency

  A blind is identified by its `ha_entity_id`. Re-running this task
  with the same entity id updates the existing row's `name` (and
  `manufacturer` / `protocol` if those flags were supplied) instead
  of raising on the unique constraint. The `sort_order` of an
  existing row is left alone so re-seeds do not perturb the FE's
  display order.

  ## Option syntax

  - `--blind <ha_entity_id>:<name>` (required, may repeat). The
    first `:` separates the entity id from the name; subsequent
    `:` characters are part of the name.
  - Flags with no value (`--blind` without an arg) raise.

  ## Exit behavior

  - Prints a one-line success message per blind.
  - Continues past per-blind errors so the rest still run, then
    exits non-zero (`Mix.raise/1`) if any failed.
  """

  use Mix.Task

  alias Core.Blinds

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest, invalid} =
      OptionParser.parse(argv,
        strict: [blind: :keep, manufacturer: :string, protocol: :string]
      )

    if invalid != [] do
      Mix.raise("unrecognized options: #{inspect(invalid)}")
    end

    case parse_blinds(opts) do
      {:ok, blinds} ->
        manufacturer = Keyword.get(opts, :manufacturer, "SmartWings")
        protocol = Keyword.get(opts, :protocol, "zwave")

        failed = seed_each(blinds, manufacturer, protocol)

        if failed != [],
          do: Mix.raise("failed to seed #{length(failed)} blind(s)"),
          else: :ok

      {:error, msg} ->
        Mix.raise(msg)
    end
  end

  defp parse_blinds(opts) do
    case Keyword.get_values(opts, :blind) do
      [] ->
        {:error, "no --blind arguments supplied"}

      raw ->
        parsed = Enum.map(raw, &parse_blind/1)

        case Enum.find(parsed, &match?({:error, _}, &1)) do
          nil -> {:ok, Enum.map(parsed, fn {:ok, v} -> v end)}
          {:error, msg} -> {:error, msg}
        end
    end
  end

  defp parse_blind(raw) do
    case String.split(raw, ":", parts: 2) do
      [ha_entity_id, name] when ha_entity_id != "" and name != "" ->
        {:ok, {ha_entity_id, name}}

      _ ->
        {:error, "invalid --blind value, expected ha_entity_id:name, got: #{inspect(raw)}"}
    end
  end

  defp seed_each(blinds, manufacturer, protocol) do
    Enum.reduce(blinds, [], fn {ha_entity_id, name}, failed ->
      case upsert(ha_entity_id, name, manufacturer, protocol) do
        {:ok, action} ->
          Mix.shell().info("#{action} #{ha_entity_id} (#{name})")
          failed

        {:error, reason} ->
          Mix.shell().error("failed to seed #{ha_entity_id} (#{name}): #{inspect(reason)}")

          [{ha_entity_id, name, reason} | failed]
      end
    end)
  end

  defp upsert(ha_entity_id, name, manufacturer, protocol) do
    base_attrs = %{
      name: name,
      manufacturer: manufacturer,
      protocol: protocol
    }

    case Blinds.get_blind_by_ha_entity_id(ha_entity_id) do
      nil ->
        attrs = Map.put(base_attrs, :ha_entity_id, ha_entity_id)

        case Blinds.create_blind(attrs) do
          {:ok, _blind} -> {:ok, "created"}
          {:error, changeset} -> {:error, changeset}
        end

      blind ->
        case Blinds.update_blind(blind, base_attrs) do
          {:ok, _blind} -> {:ok, "updated"}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end
end
