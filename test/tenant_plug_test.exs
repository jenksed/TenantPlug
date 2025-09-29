defmodule TenantPlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  doctest TenantPlug

  import TenantPlug.TestHelpers

  setup do
    clear_current()
    :ok
  end

  describe "init/1" do
    test "returns default configuration" do
      opts = TenantPlug.init([])

      assert opts.sources == [TenantPlug.Sources.FromSubdomain]
      assert opts.key == :tenant_plug_tenant
      assert opts.logger_metadata == true
      assert opts.telemetry == true
      assert opts.require_resolved == false
      assert opts.on_missing == nil
    end

    test "accepts custom configuration" do
      opts = TenantPlug.init(
        sources: [TenantPlug.Sources.FromHeader],
        key: :custom_key,
        logger_metadata: false,
        telemetry: false,
        require_resolved: true,
        on_missing: &halt_with_error/1
      )

      assert opts.sources == [TenantPlug.Sources.FromHeader]
      assert opts.key == :custom_key
      assert opts.logger_metadata == false
      assert opts.telemetry == false
      assert opts.require_resolved == true
      assert is_function(opts.on_missing)
    end
  end

  describe "call/2" do
    test "resolves tenant from configured sources" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "test-tenant")

      opts = TenantPlug.init(sources: [TenantPlug.Sources.FromHeader])
      result_conn = TenantPlug.call(conn, opts)

      assert TenantPlug.current() == "test-tenant"
      refute result_conn.halted
    end

    test "tries sources in order until one succeeds" do
      conn = %Plug.Conn{conn(:get, "/") | host: "acme.example.com"}

      opts = TenantPlug.init(
        sources: [
          TenantPlug.Sources.FromHeader,  # Will fail - no header
          TenantPlug.Sources.FromSubdomain  # Will succeed
        ]
      )

      TenantPlug.call(conn, opts)
      assert TenantPlug.current() == "acme"
    end

    test "handles case when no tenant is resolved" do
      conn = conn(:get, "/")
      opts = TenantPlug.init(sources: [TenantPlug.Sources.FromHeader])

      result_conn = TenantPlug.call(conn, opts)

      assert TenantPlug.current() == nil
      refute result_conn.halted
    end

    test "halts connection when require_resolved is true and no tenant found" do
      conn = conn(:get, "/")
      opts = TenantPlug.init(
        sources: [TenantPlug.Sources.FromHeader],
        require_resolved: true
      )

      result_conn = TenantPlug.call(conn, opts)

      assert result_conn.halted
      assert result_conn.status == 403
    end

    test "calls on_missing handler when require_resolved is true" do
      conn = conn(:get, "/")
      
      on_missing = fn conn ->
        conn
        |> Plug.Conn.send_resp(401, "Custom error")
        |> Plug.Conn.halt()
      end

      opts = TenantPlug.init(
        sources: [TenantPlug.Sources.FromHeader],
        require_resolved: true,
        on_missing: on_missing
      )

      result_conn = TenantPlug.call(conn, opts)

      assert result_conn.halted
      assert result_conn.status == 401
    end

    test "cleans up context after response" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "test-tenant")

      opts = TenantPlug.init(sources: [TenantPlug.Sources.FromHeader])
      result_conn = TenantPlug.call(conn, opts)

      # Tenant should be set during request
      assert TenantPlug.current() == "test-tenant"

      # Simulate response being sent
      result_conn
      |> Plug.Conn.send_resp(200, "OK")

      # Context should be cleared after response
      assert TenantPlug.current() == nil
    end
  end

  describe "current/0" do
    test "returns nil when no tenant is set" do
      assert TenantPlug.current() == nil
    end

    test "returns current tenant when set" do
      set_current("test-tenant")
      assert TenantPlug.current() == "test-tenant"
    end
  end

  describe "snapshot/0" do
    test "returns nil when no tenant is set" do
      assert TenantPlug.snapshot() == nil
    end

    test "returns snapshot when tenant is set" do
      set_current("test-tenant")
      snapshot = TenantPlug.snapshot()

      assert snapshot == %{tenant: "test-tenant", key: :tenant_plug_tenant}
    end
  end

  describe "apply_snapshot/1" do
    test "applies valid snapshot" do
      snapshot = %{tenant: "test-tenant", key: :tenant_plug_tenant}
      
      assert TenantPlug.apply_snapshot(snapshot) == :ok
      assert TenantPlug.current() == "test-tenant"
    end

    test "handles nil snapshot" do
      assert TenantPlug.apply_snapshot(nil) == :ok
      assert TenantPlug.current() == nil
    end

    test "returns error for invalid snapshot" do
      assert TenantPlug.apply_snapshot("invalid") == {:error, :invalid_snapshot}
    end
  end

  defp halt_with_error(conn) do
    conn
    |> Plug.Conn.send_resp(401, "Unauthorized")
    |> Plug.Conn.halt()
  end
end
