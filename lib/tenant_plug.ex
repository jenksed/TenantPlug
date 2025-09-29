defmodule TenantPlug do
  @moduledoc """
  A Plug that extracts tenant context from requests and makes it globally available.

  TenantPlug provides automatic tenant context management for Phoenix applications.
  It extracts tenant information from configurable sources (subdomain, headers, JWT),
  stores it in process-local context, and provides utilities for accessing tenant
  information throughout your application.

  ## Basic Usage

      # In your router or endpoint
      plug TenantPlug,
        sources: [
          TenantPlug.Sources.FromHeader,
          TenantPlug.Sources.FromSubdomain
        ]

      # In your controllers or contexts
      case TenantPlug.current() do
        nil -> # No tenant context
        tenant_id -> # Use tenant_id
      end

  ## Configuration Options

    * `:sources` - List of source modules or `{module, opts}` tuples to try in order
    * `:key` - Process dictionary key for storing tenant (default: `:tenant_plug_tenant`)
    * `:logger_metadata` - Whether to set Logger metadata (default: `true`)
    * `:telemetry` - Whether to emit telemetry events (default: `true`)
    * `:require_resolved` - Whether to halt requests without tenant (default: `false`)
    * `:on_missing` - Function to call when tenant required but not found

  ## Built-in Sources

    * `TenantPlug.Sources.FromHeader` - Extract from HTTP headers
    * `TenantPlug.Sources.FromSubdomain` - Extract from subdomain
    * `TenantPlug.Sources.FromJWT` - Extract from JWT claims

  ## Background Jobs

  Use snapshots to pass tenant context to background jobs:

      # In your controller
      snapshot = TenantPlug.snapshot()
      MyWorker.new(%{tenant_snapshot: snapshot, data: data})

      # In your worker
      def perform(%{tenant_snapshot: snapshot} = args) do
        TenantPlug.apply_snapshot(snapshot)
        # Now TenantPlug.current() works in this process
      end
  """

  alias TenantPlug.Context
  alias TenantPlug.Logger
  alias TenantPlug.Telemetry

  @behaviour Plug

  @type tenant :: any()
  @type source_config :: module() | {module(), map()}
  @type init_opts :: [
          sources: [source_config()],
          key: atom(),
          logger_metadata: boolean(),
          telemetry: boolean(),
          require_resolved: boolean(),
          on_missing: (Plug.Conn.t() -> Plug.Conn.t())
        ]

  @default_sources [TenantPlug.Sources.FromSubdomain]

  @impl Plug
  def init(opts) do
    %{
      sources: Keyword.get(opts, :sources, @default_sources),
      key: Keyword.get(opts, :key, :tenant_plug_tenant),
      logger_metadata: Keyword.get(opts, :logger_metadata, true),
      telemetry: Keyword.get(opts, :telemetry, true),
      require_resolved: Keyword.get(opts, :require_resolved, false),
      on_missing: Keyword.get(opts, :on_missing)
    }
  end

  @impl Plug
  def call(conn, opts) do
    case resolve_tenant(conn, opts) do
      {:ok, tenant, metadata} ->
        Context.put(tenant, opts.key)

        if opts.logger_metadata do
          Logger.attach_metadata(tenant, opts)
        end

        if opts.telemetry do
          Telemetry.emit_resolved(tenant, metadata)
        end

        conn
        |> register_cleanup(opts)

      :error ->
        handle_missing_tenant(conn, opts)
    end
  end

  @doc """
  Returns the current tenant for this process.

  This is a convenience function that delegates to `TenantPlug.Context.current/0`.

  ## Examples

      iex> TenantPlug.current()
      nil

      iex> TenantPlug.Context.put("tenant_123")
      iex> TenantPlug.current()
      "tenant_123"
  """
  @spec current() :: tenant() | nil
  def current do
    Context.current()
  end

  @doc """
  Creates a snapshot of the current tenant context.

  This is a convenience function that delegates to `TenantPlug.Context.snapshot/0`.
  Useful for passing tenant context to background jobs.

  ## Examples

      iex> TenantPlug.Context.put("tenant_123")
      iex> TenantPlug.snapshot()
      %{tenant: "tenant_123", key: :tenant_plug_tenant}
  """
  @spec snapshot() :: Context.snapshot() | nil
  def snapshot do
    Context.snapshot()
  end

  @doc """
  Applies a tenant context snapshot to the current process.

  This is a convenience function that delegates to `TenantPlug.Context.apply_snapshot/1`.

  ## Examples

      iex> snapshot = %{tenant: "tenant_123", key: :tenant_plug_tenant}
      iex> TenantPlug.apply_snapshot(snapshot)
      :ok
      iex> TenantPlug.current()
      "tenant_123"
  """
  @spec apply_snapshot(Context.snapshot() | nil) :: :ok | {:error, :invalid_snapshot}
  def apply_snapshot(snapshot) do
    Context.apply_snapshot(snapshot)
  end

  # Private functions

  defp resolve_tenant(conn, opts) do
    Enum.reduce_while(opts.sources, :error, fn source_config, _acc ->
      try do
        case extract_from_source(conn, source_config) do
          {:ok, tenant, metadata} -> {:halt, {:ok, tenant, metadata}}
          :error -> {:cont, :error}
        end
      rescue
        exception ->
          if opts.telemetry do
            Telemetry.emit_source_exception(source_config, exception)
          end

          {:cont, :error}
      end
    end)
  end

  defp extract_from_source(conn, {module, source_opts}) do
    module.extract(conn, source_opts)
  end

  defp extract_from_source(conn, module) when is_atom(module) do
    module.extract(conn, %{})
  end

  defp handle_missing_tenant(conn, %{require_resolved: false}), do: conn

  defp handle_missing_tenant(conn, %{require_resolved: true, on_missing: nil}) do
    conn
    |> Plug.Conn.send_resp(403, "Tenant required")
    |> Plug.Conn.halt()
  end

  defp handle_missing_tenant(conn, %{require_resolved: true, on_missing: handler})
       when is_function(handler, 1) do
    handler.(conn)
  end

  defp register_cleanup(conn, opts) do
    Plug.Conn.register_before_send(conn, fn conn ->
      Context.delete(opts.key)

      if opts.logger_metadata do
        Logger.clear_metadata()
      end

      if opts.telemetry do
        Telemetry.emit_cleared(Context.current(opts.key))
      end

      conn
    end)
  end
end
