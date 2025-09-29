defmodule TenantPlug.Telemetry do
  @moduledoc """
  Telemetry event emission for tenant context lifecycle.

  This module provides utilities for emitting telemetry events during tenant
  resolution, clearing, and error handling. These events can be used for
  monitoring, metrics collection, and debugging.

  ## Events

  ### `[:tenant_plug, :tenant, :resolved]`

  Emitted when a tenant is successfully resolved from a source.

  Measurements: `%{}`
  Metadata:
    * `:tenant_snapshot` - Serializable tenant representation
    * `:source` - Source that resolved the tenant (atom)
    * `:request_path` - Request path (if available)

  ### `[:tenant_plug, :tenant, :cleared]`

  Emitted when tenant context is cleared at the end of a request.

  Measurements: `%{}`
  Metadata:
    * `:tenant_snapshot` - Serializable tenant representation

  ### `[:tenant_plug, :error, :source_exception]`

  Emitted when a source raises an exception during extraction.

  Measurements: `%{}`
  Metadata:
    * `:module` - Source module that raised
    * `:reason` - Exception reason
    * `:stacktrace` - Exception stacktrace (in development only)

  ### `[:tenant_plug, :error, :source_error]`

  Emitted when a source returns an error during extraction.

  Measurements: `%{}`
  Metadata:
    * `:module` - Source module that returned error
    * `:reason` - Error reason (e.g., :not_found, :malformed_jwt)
    * `:source_config` - Source configuration used

  ## Example Handler

      :telemetry.attach(
        "tenant-metrics",
        [:tenant_plug, :tenant, :resolved],
        fn _event, _measurements, metadata, _config ->
          MyMetrics.increment("tenant.resolved", tags: %{
            source: metadata.source,
            tenant: metadata.tenant_snapshot
          })
        end,
        nil
      )
  """

  @doc """
  Emits a tenant resolved event.

  ## Examples

      iex> TenantPlug.Telemetry.emit_resolved("tenant_123", %{source: :header})
      :ok
  """
  @spec emit_resolved(any(), map()) :: :ok
  def emit_resolved(tenant, metadata) do
    event_metadata =
      metadata
      |> Map.put(:tenant_snapshot, tenant)
      |> sanitize_metadata()

    :telemetry.execute(
      [:tenant_plug, :tenant, :resolved],
      %{},
      event_metadata
    )

    :ok
  end

  @doc """
  Emits a tenant cleared event.

  ## Examples

      iex> TenantPlug.Telemetry.emit_cleared("tenant_123")
      :ok
  """
  @spec emit_cleared(any()) :: :ok
  def emit_cleared(tenant) do
    :telemetry.execute(
      [:tenant_plug, :tenant, :cleared],
      %{},
      %{tenant_snapshot: tenant}
    )

    :ok
  end

  @doc """
  Emits a source error event.

  ## Examples

      iex> TenantPlug.Telemetry.emit_source_error(MySource, :not_found)
      :ok
  """
  @spec emit_source_error(module() | {module(), map()}, term()) :: :ok
  def emit_source_error(source_config, reason) do
    module = extract_module(source_config)

    metadata = %{
      module: module,
      reason: reason,
      source_config: source_config
    }

    :telemetry.execute(
      [:tenant_plug, :error, :source_error],
      %{},
      metadata
    )

    :ok
  end

  @doc """
  Emits a source exception event.

  ## Examples

      iex> TenantPlug.Telemetry.emit_source_exception(MySource, %RuntimeError{message: "failed"})
      :ok
  """
  @spec emit_source_exception(module() | {module(), map()}, Exception.t()) :: :ok
  def emit_source_exception(source_config, exception) do
    module = extract_module(source_config)

    metadata = %{
      module: module,
      reason: Exception.message(exception)
    }

    metadata =
      if development_env?() do
        # Note: In a real implementation, you might want to capture the stacktrace
        # from the rescue clause and pass it to this function
        Map.put(metadata, :stacktrace, "stacktrace_not_available")
      else
        metadata
      end

    :telemetry.execute(
      [:tenant_plug, :error, :source_exception],
      %{},
      metadata
    )

    :ok
  end

  # Private functions

  defp sanitize_metadata(metadata) do
    metadata
    |> Map.take([:source, :tenant_snapshot, :request_path, :raw])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp extract_module({module, _opts}) when is_atom(module), do: module
  defp extract_module(module) when is_atom(module), do: module
  defp extract_module(_invalid), do: :unknown_module

  defp development_env? do
    Mix.env() == :dev
  end
end
