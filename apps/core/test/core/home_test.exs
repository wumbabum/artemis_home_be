defmodule Core.HomeTest do
  use ExUnit.Case, async: false

  import Mox

  alias Core.HA.RestClientMock
  alias Core.Home

  setup :set_mox_global
  setup :verify_on_exit!

  defp entry(overrides \\ %{}) do
    Map.merge(
      %{
        "domain" => "zwave_js",
        "entry_id" => "01KBTT53FXENZ9JQM6BF8JY9MQ",
        "title" => "Z-Wave JS",
        "state" => "loaded",
        "reason" => nil,
        "disabled_by" => nil,
        "source" => "zeroconf"
      },
      overrides
    )
  end

  describe "integration_status/1 happy path" do
    test "returns available: true when HA reports state=loaded" do
      expect(RestClientMock, :list_config_entries, fn "zwave_js" -> {:ok, [entry()]} end)

      assert {:ok, status} = Home.integration_status("zwave_js")
      assert status.available == true
      assert status.state == "loaded"
      assert status.reason == nil
      assert status.title == "Z-Wave JS"
      assert status.entry_id == "01KBTT53FXENZ9JQM6BF8JY9MQ"
    end

    test "filters server-side via the domain parameter" do
      expect(RestClientMock, :list_config_entries, fn passed_domain ->
        assert passed_domain == "zigbee"
        {:ok, []}
      end)

      assert {:ok, %{available: false}} = Home.integration_status("zigbee")
    end
  end

  describe "integration_status/1 not-installed" do
    test "returns available: false with reason=not_installed for an empty list" do
      stub(RestClientMock, :list_config_entries, fn _ -> {:ok, []} end)

      assert {:ok, status} = Home.integration_status("matter")
      assert status.available == false
      assert status.state == nil
      assert status.reason == "not_installed"
      assert status.title == nil
      assert status.entry_id == nil
    end
  end

  describe "integration_status/1 disabled" do
    test "returns reason=disabled_in_ha when disabled_by is set" do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:ok, [entry(%{"disabled_by" => "user", "state" => "not_loaded"})]}
      end)

      assert {:ok, status} = Home.integration_status("zwave_js")
      assert status.available == false
      assert status.reason == "disabled_in_ha"
      # state is still surfaced verbatim so a FE that wants the raw
      # value has it; only `reason` is normalized.
      assert status.state == "not_loaded"
      assert status.title == "Z-Wave JS"
    end

    test "disabled_by takes precedence over a loaded state" do
      # Defensive: if HA ever reports disabled_by set + state=loaded,
      # the disabled signal should still win.
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:ok, [entry(%{"disabled_by" => "config_entry"})]}
      end)

      assert {:ok, %{available: false, reason: "disabled_in_ha"}} =
               Home.integration_status("zwave_js")
    end
  end

  describe "integration_status/1 non-loaded states" do
    test "surfaces HA's reason verbatim when present" do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:ok,
         [
           entry(%{
             "state" => "setup_error",
             "reason" => "Z-Wave JS Server unreachable"
           })
         ]}
      end)

      assert {:ok, status} = Home.integration_status("zwave_js")
      assert status.available == false
      assert status.state == "setup_error"
      assert status.reason == "Z-Wave JS Server unreachable"
    end

    test "falls back to the state string when reason is nil" do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:ok, [entry(%{"state" => "setup_retry", "reason" => nil})]}
      end)

      assert {:ok, %{available: false, state: "setup_retry", reason: "setup_retry"}} =
               Home.integration_status("zwave_js")
    end
  end

  describe "integration_status/1 multiple entries" do
    test "uses the first entry when HA returns more than one" do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:ok,
         [
           entry(%{"entry_id" => "first", "title" => "First Stick"}),
           entry(%{"entry_id" => "second", "title" => "Second Stick"})
         ]}
      end)

      assert {:ok, %{entry_id: "first", title: "First Stick"}} =
               Home.integration_status("zwave_js")
    end
  end

  describe "integration_status/1 HA errors" do
    test "propagates transport failures" do
      stub(RestClientMock, :list_config_entries, fn _ -> {:error, :ha_unreachable} end)

      assert {:error, :ha_unreachable} = Home.integration_status("zwave_js")
    end

    test "propagates HA non-2xx status errors" do
      stub(RestClientMock, :list_config_entries, fn _ ->
        {:error, {:ha_status, 500, %{"message" => "boom"}}}
      end)

      assert {:error, {:ha_status, 500, _}} = Home.integration_status("zwave_js")
    end
  end
end
