defmodule TenantPlug.Sources.FromHeader do
  @moduledoc """
  Extracts tenant information from HTTP headers.

  This source looks for tenant identifiers in specified HTTP headers.
  Supports custom header names and optional value transformation.

  ## Configuration

    * `:header` - Header name to check (default: "x-tenant-id")
    * `:mapper` - Optional function to transform the header value

  ## Examples

      # For request with "X-Tenant-ID: acme"
      {:ok, "acme", %{source: :header, raw: "acme"}}

      # With custom mapper
      {:ok, %{id: "acme", source: "header"}, %{source: :header, raw: "acme"}}
  """

  @behaviour TenantPlug.Sources.Behaviour

  @default_header "x-tenant-id"

  @impl true
  def extract(conn, opts \\ %{}) do
    header_name = Map.get(opts, :header, @default_header)
    mapper = Map.get(opts, :mapper)

    case get_raw_header_value(conn, header_name) do
      nil ->
        :error

      raw_value ->
        trimmed_value = String.trim(raw_value)
        if trimmed_value == "" do
          :error
        else
          tenant = apply_mapper(trimmed_value, mapper)
          {:ok, tenant, %{source: :header, raw: raw_value}}
        end
    end
  end

  defp get_raw_header_value(conn, header_name) do
    case Plug.Conn.get_req_header(conn, String.downcase(header_name)) do
      [value | _] when byte_size(value) > 0 -> value
      [] -> nil
      [empty] when empty in ["", nil] -> nil
    end
  end

  defp apply_mapper(value, nil), do: value
  defp apply_mapper(value, mapper) when is_function(mapper, 1), do: mapper.(value)
  defp apply_mapper(value, _invalid_mapper), do: value
end