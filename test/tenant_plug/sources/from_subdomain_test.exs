defmodule TenantPlug.Sources.FromSubdomainTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias TenantPlug.Sources.FromSubdomain

  describe "extract/2 with default configuration" do
    test "extracts subdomain from valid host" do
      conn = %Plug.Conn{conn(:get, "/") | host: "acme.example.com"}

      assert FromSubdomain.extract(conn, %{}) == {:ok, "acme", %{source: :subdomain, raw: "acme.example.com"}}
    end

    test "extracts subdomain from nested subdomains" do
      conn = %Plug.Conn{conn(:get, "/") | host: "api.acme.example.com"}

      assert FromSubdomain.extract(conn, %{}) == {:ok, "api", %{source: :subdomain, raw: "api.acme.example.com"}}
    end

    test "returns error when no subdomain exists" do
      conn = %Plug.Conn{conn(:get, "/") | host: "example.com"}

      assert FromSubdomain.extract(conn, %{}) == :error
    end

    test "returns error when host header is missing" do
      conn = %Plug.Conn{conn(:get, "/") | host: nil}
      assert FromSubdomain.extract(conn, %{}) == :error
    end

    test "returns error for single part host" do
      conn = %Plug.Conn{conn(:get, "/") | host: "localhost"}

      assert FromSubdomain.extract(conn, %{}) == :error
    end

    test "returns error for empty subdomain" do
      conn = %Plug.Conn{conn(:get, "/") | host: ".example.com"}

      assert FromSubdomain.extract(conn, %{}) == :error
    end
  end

  describe "extract/2 with host_split_index option" do
    test "extracts subdomain from specified index" do
      conn = %Plug.Conn{conn(:get, "/") | host: "api.acme.example.com"}

      # Extract second part (index 1)
      opts = %{host_split_index: 1}
      assert FromSubdomain.extract(conn, opts) == {:ok, "acme", %{source: :subdomain, raw: "api.acme.example.com"}}
    end

    test "returns error when index is out of bounds" do
      conn = %Plug.Conn{conn(:get, "/") | host: "acme.example.com"}

      opts = %{host_split_index: 5}
      assert FromSubdomain.extract(conn, opts) == :error
    end

    test "handles negative index gracefully" do
      conn = %Plug.Conn{conn(:get, "/") | host: "acme.example.com"}

      opts = %{host_split_index: -1}
      assert FromSubdomain.extract(conn, opts) == :error
    end
  end

  describe "extract/2 with exclude_subdomains option" do
    test "excludes specified subdomains" do
      conn = %Plug.Conn{conn(:get, "/") | host: "www.example.com"}

      opts = %{exclude_subdomains: ["www"]}
      assert FromSubdomain.extract(conn, opts) == :error
    end

    test "allows non-excluded subdomains" do
      conn = %Plug.Conn{conn(:get, "/") | host: "acme.example.com"}

      opts = %{exclude_subdomains: ["www", "api"]}
      assert FromSubdomain.extract(conn, opts) == {:ok, "acme", %{source: :subdomain, raw: "acme.example.com"}}
    end

    test "handles multiple excluded subdomains" do
      test_cases = [
        {"www.example.com", :error},
        {"api.example.com", :error},
        {"admin.example.com", :error},
        {"acme.example.com", {:ok, "acme", %{source: :subdomain, raw: "acme.example.com"}}}
      ]

      opts = %{exclude_subdomains: ["www", "api", "admin"]}

      for {host, expected} <- test_cases do
        conn = %Plug.Conn{conn(:get, "/") | host: host}

        assert FromSubdomain.extract(conn, opts) == expected
      end
    end

    test "empty exclude list allows all subdomains" do
      conn = %Plug.Conn{conn(:get, "/") | host: "www.example.com"}

      opts = %{exclude_subdomains: []}
      assert FromSubdomain.extract(conn, opts) == {:ok, "www", %{source: :subdomain, raw: "www.example.com"}}
    end
  end

  describe "extract/2 with combined options" do
    test "applies both host_split_index and exclude_subdomains" do
      conn = %Plug.Conn{conn(:get, "/") | host: "api.www.example.com"}

      # Extract index 1 ("www") but exclude it
      opts = %{host_split_index: 1, exclude_subdomains: ["www"]}
      assert FromSubdomain.extract(conn, opts) == :error
    end

    test "extracts from index that is not excluded" do
      conn = %Plug.Conn{conn(:get, "/") | host: "api.acme.example.com"}

      # Extract index 1 ("acme") and don't exclude it
      opts = %{host_split_index: 1, exclude_subdomains: ["www", "api"]}
      assert FromSubdomain.extract(conn, opts) == {:ok, "acme", %{source: :subdomain, raw: "api.acme.example.com"}}
    end
  end

  describe "edge cases" do
    test "handles host with port" do
      conn = %Plug.Conn{conn(:get, "/") | host: "acme.example.com:4000"}

      # Note: This might need adjustment based on how you want to handle ports
      # For now, the port will be part of the last segment
      assert FromSubdomain.extract(conn, %{}) == {:ok, "acme", %{source: :subdomain, raw: "acme.example.com:4000"}}
    end

    test "handles IPv4 addresses gracefully" do
      conn = %Plug.Conn{conn(:get, "/") | host: "192.168.1.1"}

      assert FromSubdomain.extract(conn, %{}) == :error
    end

    test "handles very long subdomains" do
      long_subdomain = String.duplicate("a", 100)
      host = "#{long_subdomain}.example.com"
      
      conn = %Plug.Conn{conn(:get, "/") | host: host}

      assert FromSubdomain.extract(conn, %{}) == {:ok, long_subdomain, %{source: :subdomain, raw: host}}
    end

    test "handles international domain names" do
      conn = %Plug.Conn{conn(:get, "/") | host: "tenant.例え.テスト"}

      assert FromSubdomain.extract(conn, %{}) == {:ok, "tenant", %{source: :subdomain, raw: "tenant.例え.テスト"}}
    end

    test "handles multiple host headers" do
      # Test that conn.host takes precedence over host header
      conn = %Plug.Conn{
        conn(:get, "/") | 
        host: "acme.example.com",
        req_headers: [{"host", "other.example.com"}]
      }

      # Should use conn.host over header
      assert FromSubdomain.extract(conn, %{}) == {:ok, "acme", %{source: :subdomain, raw: "acme.example.com"}}
    end
  end
end