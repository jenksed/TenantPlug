defmodule TenantPlug.ContextTest do
  use ExUnit.Case, async: true

  alias TenantPlug.Context

  describe "put/2 and current/1" do
    test "stores and retrieves tenant with default key" do
      Context.put("test-tenant")
      assert Context.current() == "test-tenant"
    end

    test "stores and retrieves tenant with custom key" do
      Context.put("test-tenant", :custom_key)
      assert Context.current(:custom_key) == "test-tenant"
      # Default key should be empty
      assert Context.current() == nil
    end

    test "supports different tenant types" do
      # String
      Context.put("string-tenant")
      assert Context.current() == "string-tenant"

      # Integer
      Context.put(123)
      assert Context.current() == 123

      # Map
      tenant_map = %{id: "acme", name: "Acme Corp"}
      Context.put(tenant_map)
      assert Context.current() == tenant_map

      # Struct
      tenant_struct = %{__struct__: :tenant, id: "acme", name: "Acme Corp"}
      Context.put(tenant_struct)
      assert Context.current() == tenant_struct
    end
  end

  describe "delete/1" do
    test "removes tenant with default key" do
      Context.put("test-tenant")
      assert Context.current() == "test-tenant"

      Context.delete()
      assert Context.current() == nil
    end

    test "removes tenant with custom key" do
      Context.put("test-tenant", :custom_key)
      assert Context.current(:custom_key) == "test-tenant"

      Context.delete(:custom_key)
      assert Context.current(:custom_key) == nil
    end

    test "deleting one key doesn't affect others" do
      Context.put("tenant1", :key1)
      Context.put("tenant2", :key2)

      Context.delete(:key1)
      assert Context.current(:key1) == nil
      assert Context.current(:key2) == "tenant2"
    end
  end

  describe "snapshot/1" do
    test "returns nil when no tenant is set" do
      assert Context.snapshot() == nil
    end

    test "creates snapshot with default key" do
      Context.put("test-tenant")
      snapshot = Context.snapshot()

      assert snapshot == %{tenant: "test-tenant", key: :tenant_plug_tenant}
    end

    test "creates snapshot with custom key" do
      Context.put("test-tenant", :custom_key)
      snapshot = Context.snapshot(:custom_key)

      assert snapshot == %{tenant: "test-tenant", key: :custom_key}
    end

    test "snapshot includes complex tenant data" do
      tenant = %{id: "acme", name: "Acme Corp", plan: "enterprise"}
      Context.put(tenant)
      snapshot = Context.snapshot()

      assert snapshot == %{tenant: tenant, key: :tenant_plug_tenant}
    end
  end

  describe "apply_snapshot/1" do
    test "applies valid snapshot" do
      snapshot = %{tenant: "test-tenant", key: :tenant_plug_tenant}

      assert Context.apply_snapshot(snapshot) == :ok
      assert Context.current() == "test-tenant"
    end

    test "applies snapshot with custom key" do
      snapshot = %{tenant: "test-tenant", key: :custom_key}

      assert Context.apply_snapshot(snapshot) == :ok
      assert Context.current(:custom_key) == "test-tenant"
      # Default key should be empty
      assert Context.current() == nil
    end

    test "handles nil snapshot gracefully" do
      assert Context.apply_snapshot(nil) == :ok
      assert Context.current() == nil
    end

    test "returns error for invalid snapshot" do
      assert Context.apply_snapshot("invalid") == {:error, :invalid_snapshot}
      assert Context.apply_snapshot(%{}) == {:error, :invalid_snapshot}
      assert Context.apply_snapshot(%{tenant: "test"}) == {:error, :invalid_snapshot}
      assert Context.apply_snapshot(%{key: :test}) == {:error, :invalid_snapshot}
    end

    test "validates key is an atom" do
      invalid_snapshot = %{tenant: "test", key: "not_atom"}
      assert Context.apply_snapshot(invalid_snapshot) == {:error, :invalid_snapshot}
    end
  end

  describe "process isolation" do
    test "tenant context is process-local" do
      parent_pid = self()
      Context.put("parent-tenant")

      task =
        Task.async(fn ->
          # Child process should not see parent's tenant
          assert Context.current() == nil

          # Set tenant in child process
          Context.put("child-tenant")
          assert Context.current() == "child-tenant"

          # Send confirmation to parent
          send(parent_pid, :child_done)
        end)

      # Wait for child to complete
      receive do
        :child_done -> :ok
      after
        1000 -> raise "Child process timeout"
      end

      Task.await(task)

      # Parent should still have its tenant
      assert Context.current() == "parent-tenant"
    end

    test "snapshot enables cross-process context sharing" do
      Context.put("parent-tenant")
      snapshot = Context.snapshot()

      task =
        Task.async(fn ->
          # Apply snapshot in child process
          Context.apply_snapshot(snapshot)
          Context.current()
        end)

      child_tenant = Task.await(task)
      assert child_tenant == "parent-tenant"

      # Parent should still have its tenant
      assert Context.current() == "parent-tenant"
    end
  end
end
