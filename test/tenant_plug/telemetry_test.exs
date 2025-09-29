defmodule TenantPlug.TelemetryTest do
  use ExUnit.Case, async: true

  alias TenantPlug.Telemetry

  describe "emit_resolved/2" do
    test "emits resolved event with correct metadata" do
      tenant = "test_tenant"
      metadata = %{source: :header, raw: "test_tenant"}

      # Capture telemetry events
      ref = :telemetry_test.attach_event_handlers(self(), [[:tenant_plug, :tenant, :resolved]])

      assert Telemetry.emit_resolved(tenant, metadata) == :ok

      # Verify event was emitted
      assert_receive {[:tenant_plug, :tenant, :resolved], ^ref, %{}, event_metadata}
      assert event_metadata.tenant_snapshot == tenant
      assert event_metadata.source == :header
    end

    test "sanitizes metadata by removing sensitive fields" do
      tenant = "test_tenant"
      metadata = %{source: :header, raw: "test_tenant", sensitive_data: "secret", request_path: "/api/users"}

      ref = :telemetry_test.attach_event_handlers(self(), [[:tenant_plug, :tenant, :resolved]])

      Telemetry.emit_resolved(tenant, metadata)

      assert_receive {[:tenant_plug, :tenant, :resolved], ^ref, %{}, event_metadata}
      assert Map.has_key?(event_metadata, :source)
      assert Map.has_key?(event_metadata, :raw)
      refute Map.has_key?(event_metadata, :sensitive_data)
    end
  end

  describe "emit_cleared/1" do
    test "emits cleared event with tenant snapshot" do
      tenant = "test_tenant"

      ref = :telemetry_test.attach_event_handlers(self(), [[:tenant_plug, :tenant, :cleared]])

      assert Telemetry.emit_cleared(tenant) == :ok

      assert_receive {[:tenant_plug, :tenant, :cleared], ^ref, %{}, event_metadata}
      assert event_metadata.tenant_snapshot == tenant
    end
  end

  describe "emit_source_exception/2" do
    test "emits exception event for module source" do
      exception = %RuntimeError{message: "Test error"}

      ref = :telemetry_test.attach_event_handlers(self(), [[:tenant_plug, :error, :source_exception]])

      assert Telemetry.emit_source_exception(MySource, exception) == :ok

      assert_receive {[:tenant_plug, :error, :source_exception], ^ref, %{}, event_metadata}
      assert event_metadata.module == MySource
      assert event_metadata.reason == "Test error"
    end

    test "emits exception event for tuple source config" do
      exception = %RuntimeError{message: "Config error"}

      ref = :telemetry_test.attach_event_handlers(self(), [[:tenant_plug, :error, :source_exception]])

      assert Telemetry.emit_source_exception({MySource, %{option: "value"}}, exception) == :ok

      assert_receive {[:tenant_plug, :error, :source_exception], ^ref, %{}, event_metadata}
      assert event_metadata.module == MySource
      assert event_metadata.reason == "Config error"
    end

    test "includes stacktrace in development environment" do
      # Mock development environment
      original_env = Mix.env()
      Mix.env(:dev)

      exception = %RuntimeError{message: "Dev error"}

      ref = :telemetry_test.attach_event_handlers(self(), [[:tenant_plug, :error, :source_exception]])

      assert Telemetry.emit_source_exception(MySource, exception) == :ok

      assert_receive {[:tenant_plug, :error, :source_exception], ^ref, %{}, event_metadata}
      assert Map.has_key?(event_metadata, :stacktrace)

      # Restore original environment
      Mix.env(original_env)
    end

    test "excludes stacktrace in non-development environment" do
      # Ensure we're not in dev
      original_env = Mix.env()
      Mix.env(:test)

      exception = %RuntimeError{message: "Test error"}

      ref = :telemetry_test.attach_event_handlers(self(), [[:tenant_plug, :error, :source_exception]])

      assert Telemetry.emit_source_exception(MySource, exception) == :ok

      assert_receive {[:tenant_plug, :error, :source_exception], ^ref, %{}, event_metadata}
      refute Map.has_key?(event_metadata, :stacktrace)

      Mix.env(original_env)
    end
  end
end