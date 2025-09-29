defmodule TenantPlug.Sources.FromJWT do
  @moduledoc """
  Extracts tenant information from JWT tokens.

  This source parses JWT tokens from the Authorization header and extracts
  tenant information from specified claims. Requires a user-provided verifier
  function to validate and decode tokens.

  ## Configuration

    * `:claim` - JWT claim containing tenant info (default: "tenant_id")
    * `:verifier` - Module or function that validates and decodes JWT
    * `:header` - Header to check for token (default: "authorization")

  ## Verifier Function

  The verifier should accept a token string and return:
    * `{:ok, claims_map}` - Successfully decoded JWT with claims
    * `{:error, reason}` - Invalid or expired token

  ## Examples

      # For JWT with claim "tenant_id": "acme"
      {:ok, "acme", %{source: :jwt, claim: "tenant_id"}}

      # With custom claim and verifier
      opts = %{
        claim: "org_id",
        verifier: &MyApp.JWT.verify/1
      }

      # Error cases
      {:error, :missing_header}     # No authorization header
      {:error, :invalid_token}      # Token not in "Bearer <token>" format
      {:error, :malformed_jwt}      # JWT cannot be decoded
      {:error, :missing_claim}      # JWT valid but claim not present
      {:error, :no_verifier}        # No verifier function provided
  """

  @behaviour TenantPlug.Sources.Behaviour

  @default_claim "tenant_id"
  @default_header "authorization"

  @impl true
  def extract(conn, opts \\ %{}) do
    claim = Map.get(opts, :claim, @default_claim)
    verifier = Map.get(opts, :verifier)
    header = Map.get(opts, :header, @default_header)

    with {:ok, token} <- extract_token(conn, header),
         {:ok, claims} <- verify_token(token, verifier),
         {:ok, tenant} <- extract_claim(claims, claim) do
      {:ok, tenant, %{source: :jwt, claim: claim}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_token(conn, header_name) do
    case Plug.Conn.get_req_header(conn, String.downcase(header_name)) do
      [auth_header | _] ->
        case String.split(auth_header, " ", parts: 2) do
          [scheme, token] when scheme in ["Bearer", "bearer"] ->
            trimmed_token = String.trim(token)

            if trimmed_token == "" do
              {:error, :empty_token}
            else
              {:ok, trimmed_token}
            end

          _ ->
            {:error, :invalid_token}
        end

      _ ->
        {:error, :missing_header}
    end
  end

  defp verify_token(_token, nil), do: {:error, :no_verifier}

  defp verify_token(token, verifier) when is_function(verifier, 1) do
    try do
      case verifier.(token) do
        {:ok, claims} -> {:ok, claims}
        {:error, reason} -> {:error, reason}
        _other -> {:error, :malformed_jwt}
      end
    rescue
      _ -> {:error, :verifier_exception}
    end
  end

  defp verify_token(token, module) when is_atom(module) do
    try do
      case module.verify(token) do
        {:ok, claims} -> {:ok, claims}
        {:error, reason} -> {:error, reason}
        _other -> {:error, :malformed_jwt}
      end
    rescue
      _ -> {:error, :verifier_exception}
    end
  end

  defp verify_token(_token, _invalid_verifier), do: {:error, :invalid_verifier}

  defp extract_claim(claims, claim) when is_map(claims) do
    case Map.get(claims, claim) || Map.get(claims, String.to_atom(claim)) do
      nil -> {:error, :missing_claim}
      value -> {:ok, value}
    end
  end

  defp extract_claim(_claims, _claim), do: {:error, :invalid_claims}
end
