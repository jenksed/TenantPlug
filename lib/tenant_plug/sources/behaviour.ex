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

  @doc """
  Extracts tenant information from a Plug connection.

  ## Parameters

    * `conn` - The Plug connection struct
    * `opts` - Configuration options for the source

  ## Returns

    * `{:ok, tenant, metadata}` - Successfully extracted tenant with optional metadata
    * `:error` - Unable to extract tenant from this source

  ## Examples

      iex> extract(conn, %{})
      {:ok, "tenant_123", %{source: :header, raw: "tenant_123"}}

      iex> extract(conn, %{})
      :error
  """
  @callback extract(Plug.Conn.t(), opts()) ::
              {:ok, tenant(), metadata()} | :error
end