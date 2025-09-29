defmodule TenantPlug.Sources.Behaviour do
  @moduledoc """
  Behaviour for tenant extraction sources.

  Sources are responsible for extracting tenant information from incoming
  requests. Each source should implement the `extract/2` callback to parse
  the request and return either a tenant identifier or an error.
  """

  @type tenant :: any()
  @type metadata :: map()
  @type opts :: map()
  @type extraction_result ::
          {:ok, tenant(), metadata()}
          | {:error, :not_found}
          | {:error, reason :: term()}

  @doc """
  Extracts tenant information from a Plug connection.

  ## Parameters

    * `conn` - The Plug connection struct
    * `opts` - Configuration options for the source

  ## Returns

    * `{:ok, tenant, metadata}` - Successfully extracted tenant with optional metadata
    * `{:error, :not_found}` - Source applicable but no tenant found (e.g., no header present)
    * `{:error, reason}` - Source found data but failed to extract tenant (e.g., malformed JWT)

  The new error format allows sources to be more expressive about failures:
    * `{:error, :malformed_jwt}` - JWT token format is invalid
    * `{:error, :invalid_subdomain}` - Subdomain doesn't meet criteria
    * `{:error, :missing_header}` - Required header not present
    * `{:error, :empty_token}` - Token header present but empty
    * `{:error, :invalid_verifier}` - JWT verifier configuration is invalid

  ## Examples

      iex> extract(conn, %{})
      {:ok, "tenant_123", %{source: :header, raw: "tenant_123"}}

      iex> extract(conn, %{})
      {:error, :not_found}

      iex> extract(conn, %{})
      {:error, :malformed_jwt}
  """
  @callback extract(Plug.Conn.t(), opts()) :: extraction_result()
end
