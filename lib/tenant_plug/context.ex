defmodule TenantPlug.Context do
  @moduledoc """
  Process-local storage and snapshot functionality for tenant context.

  This module provides a simple interface for storing and retrieving tenant
  information within the current process, along with snapshot capabilities
  for passing context to background jobs or other processes.
  """

  @type tenant :: any()
  @type snapshot :: %{tenant: tenant(), key: atom()}

  @default_key :tenant_plug_tenant

  @doc """
  Stores a tenant value in the current process.

  ## Examples

      iex> TenantPlug.Context.put(%{id: "acme", name: "Acme Corp"})
      :ok

      iex> TenantPlug.Context.put("tenant_123")
      :ok
  """
  @spec put(tenant(), atom()) :: :ok
  def put(tenant, key \\ @default_key) do
    Process.put(key, tenant)
    :ok
  end

  @doc """
  Retrieves the current tenant from process-local storage.

  Returns `nil` if no tenant has been set.

  ## Examples

      iex> TenantPlug.Context.current()
      nil

      iex> TenantPlug.Context.put("tenant_123")
      iex> TenantPlug.Context.current()
      "tenant_123"
  """
  @spec current(atom()) :: tenant() | nil
  def current(key \\ @default_key) do
    Process.get(key)
  end

  @doc """
  Removes the tenant from process-local storage.

  ## Examples

      iex> TenantPlug.Context.put("tenant_123")
      iex> TenantPlug.Context.delete()
      :ok
      iex> TenantPlug.Context.current()
      nil
  """
  @spec delete(atom()) :: :ok
  def delete(key \\ @default_key) do
    Process.delete(key)
    :ok
  end

  @doc """
  Creates a serializable snapshot of the current tenant context.

  This snapshot can be passed to background jobs or other processes
  to restore the tenant context.

  ## Examples

      iex> TenantPlug.Context.put("tenant_123")
      iex> TenantPlug.Context.snapshot()
      %{tenant: "tenant_123", key: :tenant_plug_tenant}
  """
  @spec snapshot(atom()) :: snapshot() | nil
  def snapshot(key \\ @default_key) do
    case current(key) do
      nil -> nil
      tenant -> %{tenant: tenant, key: key}
    end
  end

  @doc """
  Applies a snapshot to the current process, restoring tenant context.

  ## Examples

      iex> snapshot = %{tenant: "tenant_123", key: :tenant_plug_tenant}
      iex> TenantPlug.Context.apply_snapshot(snapshot)
      :ok
      iex> TenantPlug.Context.current()
      "tenant_123"
  """
  @spec apply_snapshot(snapshot() | nil) :: :ok | {:error, :invalid_snapshot}
  def apply_snapshot(nil), do: :ok

  def apply_snapshot(%{tenant: tenant, key: key}) when is_atom(key) do
    put(tenant, key)
  end

  def apply_snapshot(_invalid) do
    {:error, :invalid_snapshot}
  end
end