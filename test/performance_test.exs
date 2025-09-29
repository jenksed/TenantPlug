defmodule TenantPlug.PerformanceTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  # Simple performance tests to ensure the plug is fast
  describe "performance characteristics" do
    test "plug overhead is minimal" do
      opts = TenantPlug.init(sources: [TenantPlug.Sources.FromHeader])

      # Warm up
      for _ <- 1..100 do
        conn = conn(:get, "/") |> put_req_header("x-tenant-id", "test")
        TenantPlug.call(conn, opts)
      end

      # Measure 1000 requests
      {time_microseconds, _} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            conn = conn(:get, "/") |> put_req_header("x-tenant-id", "test")
            TenantPlug.call(conn, opts)
          end
        end)

      time_per_request = time_microseconds / 1000

      # Should be faster than 100 microseconds per request (very generous)
      assert time_per_request < 100, "Average time per request: #{time_per_request} microseconds"

      # Typically should be much faster, around 10-20 microseconds
      IO.puts("Performance: #{Float.round(time_per_request, 2)} microseconds per request")
    end

    test "context operations are fast" do
      # Test 10,000 context operations
      {time_microseconds, _} =
        :timer.tc(fn ->
          for i <- 1..10000 do
            TenantPlug.Context.put("tenant_#{i}")
            TenantPlug.Context.current()
            TenantPlug.Context.delete()
          end
        end)

      # 3 operations per iteration
      time_per_operation = time_microseconds / 30000

      # Context operations should be very fast (< 1 microsecond)
      assert time_per_operation < 1,
             "Average context operation: #{time_per_operation} microseconds"

      IO.puts(
        "Context performance: #{Float.round(time_per_operation, 3)} microseconds per operation"
      )
    end

    test "snapshot operations are efficient" do
      TenantPlug.Context.put(%{id: "test", data: "some_data", extra: "more_data"})

      {time_microseconds, _} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            snapshot = TenantPlug.Context.snapshot()
            TenantPlug.Context.apply_snapshot(snapshot)
          end
        end)

      # 2 operations per iteration
      time_per_snapshot = time_microseconds / 2000

      # Snapshot operations should be fast (< 10 microseconds)
      assert time_per_snapshot < 10,
             "Average snapshot operation: #{time_per_snapshot} microseconds"

      IO.puts(
        "Snapshot performance: #{Float.round(time_per_snapshot, 2)} microseconds per operation"
      )
    end
  end
end
