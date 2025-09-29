defmodule TenantPlug.TestHelpersTest do
  use ExUnit.Case, async: true

  import TenantPlug.TestHelpers

  describe "set_current/2" do
    test "sets tenant context" do
      set_current("test-tenant")
      assert TenantPlug.current() == "test-tenant"
    end

    test "sets tenant context with custom key" do
      set_current("test-tenant", key: :custom_key)
      assert TenantPlug.Context.current(:custom_key) == "test-tenant"
      # Default key should be empty
      assert TenantPlug.current() == nil
    end

    test "sets logger metadata by default" do
      set_current("test-tenant")

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "test-tenant"
    end

    test "skips logger metadata when disabled" do
      set_current("test-tenant", logger_metadata: false)

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == nil
    end

    test "supports complex tenant data" do
      tenant = %{id: "acme", name: "Acme Corp", plan: "enterprise"}
      set_current(tenant)

      assert TenantPlug.current() == tenant
    end
  end

  describe "clear_current/1" do
    test "clears tenant context" do
      set_current("test-tenant")
      assert TenantPlug.current() == "test-tenant"

      clear_current()
      assert TenantPlug.current() == nil
    end

    test "clears tenant context with custom key" do
      set_current("test-tenant", key: :custom_key)
      assert TenantPlug.Context.current(:custom_key) == "test-tenant"

      clear_current(key: :custom_key)
      assert TenantPlug.Context.current(:custom_key) == nil
    end

    test "clears logger metadata by default" do
      set_current("test-tenant")
      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "test-tenant"

      clear_current()
      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == nil
    end

    test "skips logger metadata clearing when disabled" do
      set_current("test-tenant")

      # Manually set some other metadata to ensure it's not cleared
      Logger.metadata(other_key: "should_remain")

      clear_current(logger_metadata: false)

      # Tenant should be cleared from context but not from logger
      assert TenantPlug.current() == nil

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "test-tenant"
      assert Keyword.get(metadata, :other_key) == "should_remain"
    end

    test "clearing one key doesn't affect others" do
      set_current("tenant1", key: :key1)
      set_current("tenant2", key: :key2)

      clear_current(key: :key1)

      assert TenantPlug.Context.current(:key1) == nil
      assert TenantPlug.Context.current(:key2) == "tenant2"
    end
  end

  describe "snapshot/1" do
    test "creates snapshot of current context" do
      set_current("test-tenant")
      snapshot = snapshot()

      assert snapshot == %{tenant: "test-tenant", key: :tenant_plug_tenant}
    end

    test "creates snapshot with custom key" do
      set_current("test-tenant", key: :custom_key)
      snapshot = snapshot(key: :custom_key)

      assert snapshot == %{tenant: "test-tenant", key: :custom_key}
    end

    test "returns nil when no tenant is set" do
      clear_current()
      assert snapshot() == nil
    end
  end

  describe "apply_snapshot/1" do
    test "applies valid snapshot" do
      snapshot = %{tenant: "test-tenant", key: :tenant_plug_tenant}

      assert apply_snapshot(snapshot) == :ok
      assert TenantPlug.current() == "test-tenant"
    end

    test "handles nil snapshot" do
      assert apply_snapshot(nil) == :ok
      assert TenantPlug.current() == nil
    end

    test "returns error for invalid snapshot" do
      assert apply_snapshot("invalid") == {:error, :invalid_snapshot}
    end
  end

  describe "with_tenant/3" do
    test "temporarily sets tenant context" do
      # Start with no tenant
      clear_current()
      assert TenantPlug.current() == nil

      result =
        with_tenant("temp-tenant", fn ->
          assert TenantPlug.current() == "temp-tenant"
          "function_result"
        end)

      # Should return the function result
      assert result == "function_result"

      # Should restore to nil after function
      assert TenantPlug.current() == nil
    end

    test "restores previous tenant context" do
      set_current("original-tenant")

      result =
        with_tenant("temp-tenant", fn ->
          assert TenantPlug.current() == "temp-tenant"
          "function_result"
        end)

      assert result == "function_result"
      assert TenantPlug.current() == "original-tenant"
    end

    test "handles exceptions and still restores context" do
      set_current("original-tenant")

      assert_raise RuntimeError, "test error", fn ->
        with_tenant("temp-tenant", fn ->
          assert TenantPlug.current() == "temp-tenant"
          raise "test error"
        end)
      end

      # Should still restore original tenant even after exception
      assert TenantPlug.current() == "original-tenant"
    end

    test "works with custom key" do
      set_current("original-tenant", key: :custom_key)

      with_tenant(
        "temp-tenant",
        fn ->
          assert TenantPlug.Context.current(:custom_key) == "temp-tenant"
        end,
        key: :custom_key
      )

      assert TenantPlug.Context.current(:custom_key) == "original-tenant"
    end

    test "handles nested with_tenant calls" do
      clear_current()

      result =
        with_tenant("outer-tenant", fn ->
          assert TenantPlug.current() == "outer-tenant"

          inner_result =
            with_tenant("inner-tenant", fn ->
              assert TenantPlug.current() == "inner-tenant"
              "inner"
            end)

          # Should restore to outer tenant
          assert TenantPlug.current() == "outer-tenant"
          inner_result
        end)

      assert result == "inner"
      assert TenantPlug.current() == nil
    end

    test "passes through function arguments correctly" do
      result =
        with_tenant("test-tenant", fn ->
          # Function should be called with no arguments
          TenantPlug.current()
        end)

      assert result == "test-tenant"
    end
  end

  describe "process isolation" do
    test "test helpers don't affect other processes" do
      set_current("main-tenant")

      task =
        Task.async(fn ->
          # Child process should not see parent's tenant
          assert TenantPlug.current() == nil

          # Set tenant in child
          set_current("child-tenant")
          assert TenantPlug.current() == "child-tenant"

          # Clear in child
          clear_current()
          assert TenantPlug.current() == nil
        end)

      Task.await(task)

      # Parent should still have its tenant
      assert TenantPlug.current() == "main-tenant"
    end

    test "with_tenant doesn't affect other processes" do
      set_current("main-tenant")

      task =
        Task.async(fn ->
          # Start a with_tenant in child process
          with_tenant("child-tenant", fn ->
            # This should only affect the child process
            send(self(), TenantPlug.current())
          end)

          # Receive the tenant from within with_tenant
          receive do
            tenant -> tenant
          after
            100 -> nil
          end
        end)

      child_tenant = Task.await(task)
      assert child_tenant == "child-tenant"

      # Parent should be unaffected
      assert TenantPlug.current() == "main-tenant"
    end
  end
end
