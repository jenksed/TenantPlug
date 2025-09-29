defmodule TenantPlug.Sources.FromSubdomain do
  @moduledoc """
  Extracts tenant information from request subdomain.

  This source parses the host header to extract the subdomain as the tenant identifier.
  Supports various subdomain extraction strategies.

  ## Configuration

    * `:host_split_index` - Index to extract from split host (default: 0 for first subdomain)
    * `:exclude_subdomains` - List of subdomains to exclude (e.g., ["www", "api"])

  ## Examples

      # For request to "acme.myapp.com"
      {:ok, "acme", %{source: :subdomain, raw: "acme.myapp.com"}}

      # For request to "www.myapp.com" with exclude_subdomains: ["www"]
      :error
  """

  @behaviour TenantPlug.Sources.Behaviour

  @impl true
  def extract(conn, opts \\ %{}) do
    host_split_index = Map.get(opts, :host_split_index, 0)
    exclude_subdomains = Map.get(opts, :exclude_subdomains, [])

    case get_host(conn) do
      nil ->
        :error

      host ->
        host
        |> extract_subdomain(host_split_index)
        |> validate_subdomain(exclude_subdomains)
        |> case do
          {:ok, subdomain} ->
            {:ok, subdomain, %{source: :subdomain, raw: host}}

          :error ->
            :error
        end
    end
  end

  defp get_host(conn) do
    # Try conn.host first (set by Plug.Conn), then fall back to host header
    case conn.host do
      nil -> 
        case Plug.Conn.get_req_header(conn, "host") do
          [host | _] -> host
          [] -> nil
        end
      host -> host
    end
  end

  defp extract_subdomain(host, index) when is_binary(host) do
    # Check if it's an IP address (simple check for digits and dots)
    if is_ip_address?(host) do
      :error
    else
      parts = String.split(host, ".")

      case {index >= 0, Enum.at(parts, index)} do
        {false, _} -> :error  # Negative index not supported
        {true, nil} -> :error
        {true, ""} -> :error
        {true, subdomain} when length(parts) >= 3 -> {:ok, subdomain}  # Need at least 3 parts for subdomain
        {true, _} -> :error
      end
    end
  end

  defp is_ip_address?(host) do
    # Simple check - if all parts are numeric, it's likely an IP
    parts = String.split(host, ".")
    length(parts) == 4 and Enum.all?(parts, &numeric?/1)
  end

  defp numeric?(string) do
    case Integer.parse(string) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp validate_subdomain({:ok, subdomain}, exclude_list) do
    if subdomain in exclude_list do
      :error
    else
      {:ok, subdomain}
    end
  end

  defp validate_subdomain(:error, _exclude_list), do: :error
end