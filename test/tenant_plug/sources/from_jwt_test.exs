defmodule TenantPlug.Sources.FromJWTTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias TenantPlug.Sources.FromJWT

  # Mock JWT verifier functions
  defp successful_verifier(token) do
    case token do
      "valid_token" -> {:ok, %{"tenant_id" => "acme", "user_id" => "123"}}
      "valid_token_with_atom_claims" -> {:ok, %{tenant_id: "acme", user_id: "123"}}
      "custom_claim_token" -> {:ok, %{"org_id" => "acme_org", "tenant_id" => "ignored"}}
      _ -> {:error, :invalid_token}
    end
  end

  defp exception_verifier(_token), do: raise("JWT verification failed")

  describe "extract/2 with default configuration" do
    test "extracts tenant from valid JWT" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer valid_token")

      opts = %{verifier: &successful_verifier/1}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end

    test "handles JWT with atom keys" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer valid_token_with_atom_claims")

      opts = %{verifier: &successful_verifier/1}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end

    test "returns error when no authorization header" do
      conn = conn(:get, "/")
      opts = %{verifier: &successful_verifier/1}

      assert FromJWT.extract(conn, opts) == {:error, :missing_header}
    end

    test "returns error when authorization header is not Bearer" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Basic dXNlcjpwYXNz")

      opts = %{verifier: &successful_verifier/1}

      assert FromJWT.extract(conn, opts) == {:error, :invalid_token}
    end

    test "returns error when JWT verification fails" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer invalid_token")

      opts = %{verifier: &successful_verifier/1}

      assert FromJWT.extract(conn, opts) == {:error, :invalid_token}
    end

    test "returns error when verifier is not provided" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer valid_token")

      assert FromJWT.extract(conn, %{}) == {:error, :no_verifier}
    end

    test "returns error when tenant claim is missing" do
      missing_claim_verifier = fn _token -> {:ok, %{"user_id" => "123"}} end

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer valid_token")

      opts = %{verifier: missing_claim_verifier}

      assert FromJWT.extract(conn, opts) == {:error, :missing_claim}
    end
  end

  describe "extract/2 with custom claim" do
    test "extracts tenant from custom claim" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer custom_claim_token")

      opts = %{verifier: &successful_verifier/1, claim: "org_id"}

      assert FromJWT.extract(conn, opts) == {:ok, "acme_org", %{source: :jwt, claim: "org_id"}}
    end

    test "ignores default claim when custom claim is specified" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer custom_claim_token")

      # This token has both "org_id" and "tenant_id", but we want "org_id"
      opts = %{verifier: &successful_verifier/1, claim: "org_id"}

      assert FromJWT.extract(conn, opts) == {:ok, "acme_org", %{source: :jwt, claim: "org_id"}}
    end
  end

  describe "extract/2 with custom header" do
    test "extracts JWT from custom header" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-auth-token", "Bearer valid_token")

      opts = %{verifier: &successful_verifier/1, header: "x-auth-token"}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end

    test "handles case insensitive custom headers" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-auth-token", "Bearer valid_token")

      opts = %{verifier: &successful_verifier/1, header: "x-auth-token"}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end
  end

  describe "extract/2 with different verifier types" do
    test "handles function verifier" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer valid_token")

      opts = %{verifier: &successful_verifier/1}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end

    test "handles module verifier" do
      defmodule MockJWTModule do
        def verify("valid_token"), do: {:ok, %{"tenant_id" => "acme"}}
        def verify(_), do: {:error, :invalid_token}
      end

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer valid_token")

      opts = %{verifier: MockJWTModule}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end

    test "handles verifier that raises exception" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer any_token")

      opts = %{verifier: &exception_verifier/1}

      assert FromJWT.extract(conn, opts) == {:error, :verifier_exception}
    end

    test "handles invalid verifier type" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer valid_token")

      opts = %{verifier: "not_a_function_or_module"}

      assert FromJWT.extract(conn, opts) == {:error, :invalid_verifier}
    end
  end

  describe "token extraction edge cases" do
    test "handles Bearer with different cases" do
      test_cases = [
        "Bearer valid_token",
        "bearer valid_token"
      ]

      opts = %{verifier: &successful_verifier/1}

      for auth_header <- test_cases do
        conn =
          conn(:get, "/")
          |> put_req_header("authorization", auth_header)

        assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
      end
    end

    test "trims whitespace from token" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer  valid_token  ")

      opts = %{verifier: &successful_verifier/1}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end

    test "returns error for malformed authorization header" do
      test_cases = [
        # Missing token
        {"Bearer", {:error, :invalid_token}},
        # Empty token
        {"Bearer ", {:error, :empty_token}},
        # Wrong scheme
        {"Basic valid_token", {:error, :invalid_token}},
        # Missing scheme
        {"valid_token", {:error, :invalid_token}},
        # Empty header
        {"", {:error, :invalid_token}}
      ]

      opts = %{verifier: &successful_verifier/1}

      for {auth_header, expected_error} <- test_cases do
        conn =
          conn(:get, "/")
          |> put_req_header("authorization", auth_header)

        assert FromJWT.extract(conn, opts) == expected_error
      end
    end

    test "handles very long tokens" do
      long_token = String.duplicate("a", 2000)
      long_token_verifier = fn ^long_token -> {:ok, %{"tenant_id" => "acme"}} end

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer #{long_token}")

      opts = %{verifier: long_token_verifier}

      assert FromJWT.extract(conn, opts) == {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}
    end
  end

  describe "claims extraction edge cases" do
    test "handles claims with nil values" do
      nil_claim_verifier = fn _token -> {:ok, %{"tenant_id" => nil, "user_id" => "123"}} end

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer token")

      opts = %{verifier: nil_claim_verifier}

      assert FromJWT.extract(conn, opts) == {:error, :missing_claim}
    end

    test "handles non-map claims" do
      invalid_claims_verifier = fn _token -> {:ok, "not_a_map"} end

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer token")

      opts = %{verifier: invalid_claims_verifier}

      assert FromJWT.extract(conn, opts) == {:error, :invalid_claims}
    end

    test "prefers string keys over atom keys when both exist" do
      mixed_keys_verifier = fn _token ->
        {:ok, %{"tenant_id" => "string_value", :tenant_id => "atom_value"}}
      end

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer token")

      opts = %{verifier: mixed_keys_verifier}

      assert FromJWT.extract(conn, opts) ==
               {:ok, "string_value", %{source: :jwt, claim: "tenant_id"}}
    end
  end
end
