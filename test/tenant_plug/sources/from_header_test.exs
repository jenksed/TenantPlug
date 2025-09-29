defmodule TenantPlug.Sources.FromHeaderTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias TenantPlug.Sources.FromHeader

  describe "extract/2" do
    test "extracts tenant from default header" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "acme")

      assert FromHeader.extract(conn, %{}) == {:ok, "acme", %{source: :header, raw: "acme"}}
    end

    test "extracts tenant from custom header" do
      conn =
        conn(:get, "/")
        |> put_req_header("tenant", "acme")

      opts = %{header: "tenant"}
      assert FromHeader.extract(conn, opts) == {:ok, "acme", %{source: :header, raw: "acme"}}
    end

    test "header names are case insensitive" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "acme")

      assert FromHeader.extract(conn, %{}) == {:ok, "acme", %{source: :header, raw: "acme"}}
    end

    test "trims whitespace from header values" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "  acme  ")

      assert FromHeader.extract(conn, %{}) == {:ok, "acme", %{source: :header, raw: "  acme  "}}
    end

    test "returns error when header is missing" do
      conn = conn(:get, "/")
      assert FromHeader.extract(conn, %{}) == :error
    end

    test "returns error when header is empty" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "")

      assert FromHeader.extract(conn, %{}) == :error
    end

    test "returns error when header is only whitespace" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "   ")

      assert FromHeader.extract(conn, %{}) == :error
    end

    test "uses first header value when multiple are present" do
      conn = %Plug.Conn{
        conn(:get, "/") | 
        req_headers: [{"x-tenant-id", "first"}, {"x-tenant-id", "second"}]
      }

      assert FromHeader.extract(conn, %{}) == {:ok, "first", %{source: :header, raw: "first"}}
    end
  end

  describe "mapper option" do
    test "applies mapper function to transform value" do
      mapper = fn value -> String.upcase(value) end
      
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "acme")

      opts = %{mapper: mapper}
      assert FromHeader.extract(conn, opts) == {:ok, "ACME", %{source: :header, raw: "acme"}}
    end

    test "mapper can return complex data structures" do
      mapper = fn value -> %{id: value, source: "header"} end
      
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "acme")

      opts = %{mapper: mapper}
      expected_tenant = %{id: "acme", source: "header"}
      
      assert FromHeader.extract(conn, opts) == {:ok, expected_tenant, %{source: :header, raw: "acme"}}
    end

    test "ignores invalid mapper" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "acme")

      opts = %{mapper: "not_a_function"}
      assert FromHeader.extract(conn, opts) == {:ok, "acme", %{source: :header, raw: "acme"}}
    end

    test "handles mapper with wrong arity" do
      mapper = fn _a, _b -> "wrong_arity" end
      
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "acme")

      opts = %{mapper: mapper}
      assert FromHeader.extract(conn, opts) == {:ok, "acme", %{source: :header, raw: "acme"}}
    end

    test "handles nil mapper" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", "acme")

      opts = %{mapper: nil}
      assert FromHeader.extract(conn, opts) == {:ok, "acme", %{source: :header, raw: "acme"}}
    end
  end

  describe "edge cases" do
    test "handles very long header values" do
      long_value = String.duplicate("a", 1000)
      
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", long_value)

      assert FromHeader.extract(conn, %{}) == {:ok, long_value, %{source: :header, raw: long_value}}
    end

    test "handles special characters in header values" do
      special_value = "tenant-123_test.com"
      
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", special_value)

      assert FromHeader.extract(conn, %{}) == {:ok, special_value, %{source: :header, raw: special_value}}
    end

    test "handles unicode characters in header values" do
      unicode_value = "租户-123"
      
      conn =
        conn(:get, "/")
        |> put_req_header("x-tenant-id", unicode_value)

      assert FromHeader.extract(conn, %{}) == {:ok, unicode_value, %{source: :header, raw: unicode_value}}
    end
  end
end