defmodule TenantPlug.LoggerTest do
  # Logger metadata is global
  use ExUnit.Case, async: false
  require Logger

  alias TenantPlug.Logger, as: TenantLogger

  setup do
    # Clear metadata before each test
    Logger.reset_metadata([])
    :ok
  end

  describe "attach_metadata/2" do
    test "sets tenant_id metadata for string tenant" do
      TenantLogger.attach_metadata("tenant_123")

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "tenant_123"
      refute Keyword.has_key?(metadata, :tenant)
    end

    test "sets tenant_id metadata for integer tenant" do
      TenantLogger.attach_metadata(123)

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == 123
    end

    test "extracts id from map with string key" do
      tenant = %{"id" => "map_tenant"}
      TenantLogger.attach_metadata(tenant)

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "map_tenant"
    end

    test "extracts id from map with atom key" do
      tenant = %{id: "atom_tenant"}
      TenantLogger.attach_metadata(tenant)

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "atom_tenant"
    end

    test "uses inspect for complex tenant without id" do
      tenant = %{name: "Complex Corp", plan: "enterprise"}
      TenantLogger.attach_metadata(tenant)

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == inspect(tenant)
    end

    test "includes full tenant when include_full_tenant is true" do
      tenant = %{id: "acme", name: "Acme Corp"}
      TenantLogger.attach_metadata(tenant, %{include_full_tenant: true})

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "acme"
      assert Keyword.get(metadata, :tenant) == tenant
    end

    test "excludes full tenant when include_full_tenant is false" do
      tenant = %{id: "acme", name: "Acme Corp"}
      TenantLogger.attach_metadata(tenant, %{include_full_tenant: false})

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "acme"
      refute Keyword.has_key?(metadata, :tenant)
    end

    test "preserves existing metadata" do
      Logger.metadata(existing_key: "existing_value")
      TenantLogger.attach_metadata("tenant_123")

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "tenant_123"
      assert Keyword.get(metadata, :existing_key) == "existing_value"
    end
  end

  describe "clear_metadata/0" do
    test "removes tenant_id metadata" do
      Logger.metadata(tenant_id: "test_tenant")
      TenantLogger.clear_metadata()

      metadata = Logger.metadata()
      refute Keyword.has_key?(metadata, :tenant_id)
    end

    test "removes tenant metadata" do
      Logger.metadata(tenant: %{id: "test"})
      TenantLogger.clear_metadata()

      metadata = Logger.metadata()
      refute Keyword.has_key?(metadata, :tenant)
    end

    test "preserves non-tenant metadata" do
      Logger.metadata(tenant_id: "test", other_key: "preserve_me")
      TenantLogger.clear_metadata()

      metadata = Logger.metadata()
      refute Keyword.has_key?(metadata, :tenant_id)
      assert Keyword.get(metadata, :other_key) == "preserve_me"
    end

    test "handles empty metadata gracefully" do
      Logger.reset_metadata([])
      assert TenantLogger.clear_metadata() == :ok

      metadata = Logger.metadata()
      assert metadata == []
    end
  end
end
