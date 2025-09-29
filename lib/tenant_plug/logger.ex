defmodule TenantPlug.Logger do
  @moduledoc """
  Logger metadata integration for tenant context.

  This module provides utilities for attaching tenant information to Logger
  metadata, making it available in log entries throughout the request lifecycle.
  """

  require Logger

  @doc """
  Attaches tenant metadata to the current process Logger context.

  ## Metadata Keys

    * `:tenant_id` - The tenant identifier (always set)
    * `:tenant` - The full tenant struct/map (optional, based on configuration)

  ## Options

    * `:include_full_tenant` - Whether to include the full tenant in metadata (default: false)

  ## Examples

      iex> TenantPlug.Logger.attach_metadata("tenant_123")
      :ok

      iex> TenantPlug.Logger.attach_metadata(%{id: "tenant_123", name: "Acme"}, %{include_full_tenant: true})
      :ok
  """
  @spec attach_metadata(any(), map()) :: :ok
  def attach_metadata(tenant, opts \\ %{}) do
    include_full = Map.get(opts, :include_full_tenant, false)

    metadata = build_metadata(tenant, include_full)
    Logger.metadata(metadata)

    :ok
  end

  @doc """
  Clears tenant-related metadata from the current process Logger context.

  ## Examples

      iex> TenantPlug.Logger.clear_metadata()
      :ok
  """
  @spec clear_metadata() :: :ok
  def clear_metadata do
    current_metadata = Logger.metadata()

    new_metadata =
      current_metadata
      |> Keyword.delete(:tenant_id)
      |> Keyword.delete(:tenant)

    Logger.reset_metadata(new_metadata)
    :ok
  end

  # Private functions

  defp build_metadata(tenant, include_full) do
    base_metadata = [tenant_id: extract_tenant_id(tenant)]

    if include_full do
      Keyword.put(base_metadata, :tenant, tenant)
    else
      base_metadata
    end
  end

  defp extract_tenant_id(tenant) when is_binary(tenant) or is_integer(tenant), do: tenant
  defp extract_tenant_id(%{id: id}), do: id
  defp extract_tenant_id(%{"id" => id}), do: id
  defp extract_tenant_id(tenant), do: inspect(tenant)
end
