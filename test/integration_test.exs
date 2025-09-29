defmodule TenantPlug.IntegrationTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  describe "full integration scenarios" do
    @tag :skip
    test "real-world multi-source configuration" do
      # Configure plug with multiple sources like a real app would
      opts =
        TenantPlug.init(
          sources: [
            {TenantPlug.Sources.FromHeader, header: "x-priority-tenant"},
            {TenantPlug.Sources.FromHeader, header: "x-organization-id"},
            {TenantPlug.Sources.FromSubdomain, exclude_subdomains: ["www"]}
          ],
          logger_metadata: true,
          telemetry: true,
          require_resolved: false
        )

      # Test priority header source (highest priority)  
      conn_priority =
        conn(:get, "/api/users")
        |> put_req_header("x-priority-tenant", "priority_tenant")
        |> put_req_header("x-organization-id", "header_tenant")

      result = TenantPlug.call(conn_priority, opts)
      IO.inspect(TenantPlug.current(), label: "Current tenant")
      assert TenantPlug.current() == "priority_tenant"
      refute result.halted

      # Clear context
      TenantPlug.Context.delete()

      # Test header source (fallback)
      conn_header =
        %Plug.Conn{conn(:get, "/api/users") | host: nil}
        |> put_req_header("x-organization-id", "header_tenant")

      TenantPlug.call(conn_header, opts)
      assert TenantPlug.current() == "header_tenant"

      # Clear context
      TenantPlug.Context.delete()

      # Test subdomain source (last fallback)
      conn_subdomain = %Plug.Conn{conn(:get, "/api/users") | host: "acme.app.com"}

      TenantPlug.call(conn_subdomain, opts)
      assert TenantPlug.current() == "acme"
    end

    test "enforced tenant with custom error handler" do
      error_handler = fn conn ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(401, ~s({"error": "tenant_required", "code": "MISSING_TENANT"}))
        |> halt()
      end

      opts =
        TenantPlug.init(
          sources: [TenantPlug.Sources.FromHeader],
          require_resolved: true,
          on_missing: error_handler
        )

      conn = conn(:get, "/api/protected")
      result = TenantPlug.call(conn, opts)

      assert result.halted
      assert result.status == 401
      assert get_resp_header(result, "content-type") == ["application/json"]
    end

    test "background job workflow" do
      # Simulate a web request that sets tenant context
      TenantPlug.Context.put(%{id: "acme", plan: "enterprise", features: ["feature_a"]})

      # Create snapshot for background job
      snapshot = TenantPlug.snapshot()
      assert snapshot.tenant.id == "acme"

      # Simulate background job in different process
      task =
        Task.async(fn ->
          # Apply snapshot in worker process
          TenantPlug.apply_snapshot(snapshot)

          # Verify tenant context is available
          current_tenant = TenantPlug.current()

          # Simulate job work
          {current_tenant.id, current_tenant.plan}
        end)

      {tenant_id, plan} = Task.await(task)
      assert tenant_id == "acme"
      assert plan == "enterprise"
    end

    test "logger metadata integration" do
      # Clear any existing metadata
      Logger.reset_metadata([])

      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "logger_test_tenant")

      opts =
        TenantPlug.init(
          sources: [TenantPlug.Sources.FromHeader],
          logger_metadata: true
        )

      TenantPlug.call(conn, opts)

      # Check that logger metadata was set
      metadata = Logger.metadata()
      assert Keyword.get(metadata, :tenant_id) == "logger_test_tenant"

      # Simulate response completion (cleanup)
      TenantPlug.Logger.clear_metadata()

      metadata_after = Logger.metadata()
      assert Keyword.get(metadata_after, :tenant_id) == nil
    end

    test "telemetry events integration" do
      # Attach test telemetry handler
      test_pid = self()

      :telemetry.attach(
        "tenant_test_handler",
        [:tenant_plug, :tenant, :resolved],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      try do
        conn =
          conn(:get, "/")
          |> put_req_header("x-tenant-id", "telemetry_tenant")

        opts =
          TenantPlug.init(
            sources: [TenantPlug.Sources.FromHeader],
            telemetry: true
          )

        TenantPlug.call(conn, opts)

        # Verify telemetry event was emitted
        assert_receive {:telemetry, [:tenant_plug, :tenant, :resolved], %{}, metadata}
        assert metadata.tenant_snapshot == "telemetry_tenant"
        assert metadata.source == :header
      after
        :telemetry.detach("tenant_test_handler")
      end
    end

    test "error handling in source chain" do
      # Create a source that raises an exception
      defmodule FaultySource do
        @behaviour TenantPlug.Sources.Behaviour

        def extract(_conn, _opts) do
          raise "Simulated source error"
        end
      end

      opts =
        TenantPlug.init(
          sources: [
            # This will raise
            FaultySource,
            # This should still work
            TenantPlug.Sources.FromHeader
          ],
          telemetry: true
        )

      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "backup_tenant")

      # Should not crash and should fall back to header source
      result = TenantPlug.call(conn, opts)

      assert TenantPlug.current() == "backup_tenant"
      refute result.halted
    end

    test "concurrent tenant contexts" do
      # Test that different processes have isolated tenant contexts
      parent_tenant = "parent_tenant"
      TenantPlug.Context.put(parent_tenant)

      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            child_tenant = "child_tenant_#{i}"
            TenantPlug.Context.put(child_tenant)

            # Simulate some work
            :timer.sleep(1)

            # Verify isolation
            {TenantPlug.current(), child_tenant}
          end)
        end

      results = Task.await_many(tasks)

      # All child processes should have their own context
      for {actual, expected} <- results do
        assert actual == expected
      end

      # Parent process should still have its context
      assert TenantPlug.current() == parent_tenant
    end
  end

  # Mock JWT verifier for testing
  def mock_jwt_verifier("valid_jwt_token") do
    {:ok, %{"org_id" => "jwt_tenant", "user_id" => "123"}}
  end

  def mock_jwt_verifier(_), do: {:error, :invalid_token}
end
