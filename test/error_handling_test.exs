defmodule TenantPlug.ErrorHandlingTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  describe "robust error handling" do
    test "handles malformed JWT tokens gracefully" do
      malformed_verifier = fn _token -> raise ArgumentError, "Invalid JWT format" end

      opts =
        TenantPlug.init(
          sources: [
            {TenantPlug.Sources.FromJWT, verifier: malformed_verifier},
            TenantPlug.Sources.FromHeader
          ],
          # Disable to avoid telemetry noise in tests
          telemetry: false
        )

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer malformed_token")
        |> put_req_header("x-tenant-id", "fallback_tenant")

      # Should not crash and fall back to header
      result = TenantPlug.call(conn, opts)
      assert TenantPlug.current() == "fallback_tenant"
      refute result.halted
    end

    test "handles extremely long header values" do
      # Test with 10KB header value
      long_tenant_id = String.duplicate("x", 10000)

      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", long_tenant_id)

      opts = TenantPlug.init(sources: [TenantPlug.Sources.FromHeader])

      result = TenantPlug.call(conn, opts)
      assert TenantPlug.current() == long_tenant_id
      refute result.halted
    end

    test "handles malformed host headers" do
      test_hosts = [
        # Empty host
        "",
        # Just dot
        ".",
        # Multiple dots
        "...",
        # Very long single part
        String.duplicate("x", 1000)
      ]

      opts = TenantPlug.init(sources: [TenantPlug.Sources.FromSubdomain])

      for host <- test_hosts do
        conn = %Plug.Conn{conn(:get, "/") | host: host}

        # Should not crash, should return no tenant
        result = TenantPlug.call(conn, opts)
        assert TenantPlug.current() == nil
        refute result.halted

        # Clear for next iteration
        TenantPlug.Context.delete()
      end
    end

    test "handles process dictionary corruption gracefully" do
      # Test with invalid process dictionary state
      Process.put(:tenant_plug_tenant, :invalid_atom_instead_of_tenant)

      # Context operations should handle this gracefully
      current = TenantPlug.Context.current()
      assert current == :invalid_atom_instead_of_tenant

      # Snapshot should work with any data type
      snapshot = TenantPlug.Context.snapshot()
      assert snapshot == %{tenant: :invalid_atom_instead_of_tenant, key: :tenant_plug_tenant}

      # Applying snapshot should work
      TenantPlug.Context.delete()
      assert TenantPlug.Context.apply_snapshot(snapshot) == :ok
      assert TenantPlug.Context.current() == :invalid_atom_instead_of_tenant
    end

    test "handles memory pressure scenarios" do
      # Test with very large tenant data structures
      large_tenant = %{
        id: "memory_test",
        data: for(i <- 1..1000, do: {"key_#{i}", String.duplicate("value", 100)}),
        nested: %{
          deep: %{
            structure: for(j <- 1..100, do: %{id: j, data: String.duplicate("x", 50)})
          }
        }
      }

      TenantPlug.Context.put(large_tenant)

      # Operations should still work
      assert TenantPlug.Context.current() == large_tenant

      snapshot = TenantPlug.Context.snapshot()
      assert snapshot.tenant == large_tenant

      TenantPlug.Context.delete()
      TenantPlug.Context.apply_snapshot(snapshot)
      assert TenantPlug.Context.current() == large_tenant
    end

    test "handles invalid source configurations" do
      invalid_configs = [
        # nil source
        nil,
        # string instead of module
        "not_a_module",
        # module that doesn't implement behaviour
        {String, %{}},
        # invalid options
        {TenantPlug.Sources.FromHeader, "not_a_map"}
      ]

      for config <- invalid_configs do
        opts = TenantPlug.init(sources: [config])
        conn = conn(:get, "/") |> put_req_header("x-tenant-id", "test")

        # Should not crash the application
        result = TenantPlug.call(conn, opts)

        # Most likely will not resolve tenant but shouldn't crash
        refute result.halted

        TenantPlug.Context.delete()
      end
    end

    test "handles circular snapshot references" do
      # Create a tenant with self-reference (edge case)
      circular_tenant = %{id: "circular", self: nil}
      circular_tenant = %{circular_tenant | self: circular_tenant}

      TenantPlug.Context.put(circular_tenant)

      # Snapshot should handle this without infinite recursion
      snapshot = TenantPlug.Context.snapshot()
      assert is_map(snapshot)
      assert Map.has_key?(snapshot, :tenant)

      # Apply should work
      TenantPlug.Context.delete()
      assert TenantPlug.Context.apply_snapshot(snapshot) == :ok
    end

    test "handles unicode and special characters" do
      unicode_tenants = [
        # Chinese characters
        "租户-123",
        # Cyrillic
        "тенант_456",
        # Emoji
        "🏢-tenant-789",
        # Null bytes
        "tenant\x00null",
        # Control characters
        "tenant\ttab\nnewline"
      ]

      opts = TenantPlug.init(sources: [TenantPlug.Sources.FromHeader])

      for tenant <- unicode_tenants do
        conn = conn(:get, "/") |> put_req_header("x-tenant-id", tenant)

        result = TenantPlug.call(conn, opts)
        assert TenantPlug.current() == tenant
        refute result.halted

        # Test logger metadata with unicode
        TenantPlug.Logger.attach_metadata(tenant)
        metadata = Logger.metadata()
        assert Keyword.get(metadata, :tenant_id) == tenant

        TenantPlug.Logger.clear_metadata()
        TenantPlug.Context.delete()
      end
    end

    test "handles concurrent modifications safely" do
      # Test concurrent access to process dictionary
      TenantPlug.Context.put("initial_tenant")

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            # Each task tries to modify the same key concurrently
            tenant = "concurrent_tenant_#{i}"
            TenantPlug.Context.put(tenant)

            # Small delay to increase chance of race conditions
            :timer.sleep(1)

            TenantPlug.Context.current()
          end)
        end

      results = Task.await_many(tasks)

      # All tasks should complete successfully
      assert length(results) == 10

      # Each should have their own value (process isolation)
      for {result, i} <- Enum.with_index(results) do
        expected = "concurrent_tenant_#{i + 1}"
        assert result == expected
      end
    end

    test "handles logger metadata edge cases" do
      edge_case_tenants = [
        # nil tenant
        nil,
        # empty string
        "",
        # empty map
        %{},
        # map without id
        %{not_id: "value"},
        # list (unexpected type)
        [],
        # tuple
        {:tuple, "value"},
        # function
        fn -> "function" end
      ]

      for tenant <- edge_case_tenants do
        # Should not crash
        TenantPlug.Logger.attach_metadata(tenant)

        metadata = Logger.metadata()
        tenant_id = Keyword.get(metadata, :tenant_id)

        # Should have some representation
        assert tenant_id != nil

        TenantPlug.Logger.clear_metadata()
      end
    end
  end
end
