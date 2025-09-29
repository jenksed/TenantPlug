defmodule TenantPlug.TestHelpers do
  @moduledoc """
  Test utilities for managing tenant context in tests.

  This module provides convenient functions for setting up and tearing down
  tenant context in your test suite, allowing you to test tenant-scoped
  functionality without going through the full plug pipeline.

  ## Usage in Tests

      defmodule MyAppTest do
        use ExUnit.Case
        import TenantPlug.TestHelpers

        setup do
          # Set up tenant context for each test
          set_current("test_tenant")

          on_exit(fn ->
            clear_current()
          end)
        end

        test "tenant-scoped functionality" do
          assert TenantPlug.current() == "test_tenant"
          # Your test code here
        end
      end

  ## ExUnit Case Template

  For projects that heavily use tenant context, you might want to create
  a case template:

      defmodule MyApp.TenantCase do
        use ExUnit.CaseTemplate

        using do
          quote do
            import TenantPlug.TestHelpers
          end
        end

        setup do
          TenantPlug.TestHelpers.clear_current()
          :ok
        end
      end

  Then use it in your tests:

      defmodule MyFeatureTest do
        use MyApp.TenantCase

        test "with tenant context" do
          set_current(%{id: "acme", plan: "enterprise"})
          # Test tenant-specific behavior
        end
      end
  """

  alias TenantPlug.Context
  alias TenantPlug.Logger

  @doc """
  Sets the current tenant context for the test process.

  This function mimics the behavior of the TenantPlug during a request,
  including setting Logger metadata if configured.

  ## Examples

      iex> TenantPlug.TestHelpers.set_current("test_tenant")
      :ok

      iex> TenantPlug.TestHelpers.set_current(%{id: "acme", name: "Acme Corp"})
      :ok
  """
  @spec set_current(any(), keyword()) :: :ok
  def set_current(tenant, opts \\ []) do
    key = Keyword.get(opts, :key, :tenant_plug_tenant)
    logger_metadata = Keyword.get(opts, :logger_metadata, true)

    Context.put(tenant, key)

    if logger_metadata do
      Logger.attach_metadata(tenant, %{})
    end

    :ok
  end

  @doc """
  Clears the current tenant context from the test process.

  This function cleans up both the process-local storage and Logger metadata.

  ## Examples

      iex> TenantPlug.TestHelpers.set_current("test_tenant")
      iex> TenantPlug.TestHelpers.clear_current()
      :ok
      iex> TenantPlug.current()
      nil
  """
  @spec clear_current(keyword()) :: :ok
  def clear_current(opts \\ []) do
    key = Keyword.get(opts, :key, :tenant_plug_tenant)
    logger_metadata = Keyword.get(opts, :logger_metadata, true)

    Context.delete(key)

    if logger_metadata do
      Logger.clear_metadata()
    end

    :ok
  end

  @doc """
  Creates a snapshot for the current test tenant context.

  Useful for testing background job scenarios where you need to pass
  tenant context between processes.

  ## Examples

      iex> TenantPlug.TestHelpers.set_current("test_tenant")
      iex> snapshot = TenantPlug.TestHelpers.snapshot()
      iex> # Use snapshot in background job tests
  """
  @spec snapshot(keyword()) :: Context.snapshot() | nil
  def snapshot(opts \\ []) do
    key = Keyword.get(opts, :key, :tenant_plug_tenant)
    Context.snapshot(key)
  end

  @doc """
  Applies a tenant snapshot in the test process.

  This is equivalent to `TenantPlug.apply_snapshot/1` but provides
  consistency with other test helper functions.

  ## Examples

      iex> snapshot = %{tenant: "test_tenant", key: :tenant_plug_tenant}
      iex> TenantPlug.TestHelpers.apply_snapshot(snapshot)
      :ok
  """
  @spec apply_snapshot(Context.snapshot() | nil) :: :ok | {:error, :invalid_snapshot}
  def apply_snapshot(snapshot) do
    Context.apply_snapshot(snapshot)
  end

  @doc """
  Temporarily sets tenant context for the duration of a function.

  This is useful for testing specific scenarios without affecting the
  broader test setup.

  ## Examples

      iex> TenantPlug.TestHelpers.with_tenant("temp_tenant", fn ->
      ...>   assert TenantPlug.current() == "temp_tenant"
      ...>   # Test code here
      ...> end)
      :ok
  """
  @spec with_tenant(any(), (() -> any()), keyword()) :: any()
  def with_tenant(tenant, fun, opts \\ []) when is_function(fun, 0) do
    key = Keyword.get(opts, :key, :tenant_plug_tenant)
    previous_tenant = Context.current(key)

    try do
      set_current(tenant, opts)
      fun.()
    after
      if previous_tenant do
        set_current(previous_tenant, opts)
      else
        clear_current(opts)
      end
    end
  end
end