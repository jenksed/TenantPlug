# TenantPlug

A lightweight Elixir library for automatic tenant context management in Phoenix applications.

## Features

- 🏢 **Automatic tenant extraction** from subdomains, headers, or JWT tokens
- 🔄 **Process-local context** for safe, global access during request lifecycle
- 📊 **Logger metadata integration** for better observability
- 📈 **Telemetry events** for monitoring and metrics
- 🧪 **Test helpers** for easy testing of tenant-scoped functionality
- 🔧 **Pluggable sources** for custom tenant extraction strategies

## Installation

Add `tenant_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tenant_plug, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Add the plug to your router or endpoint

```elixir
# In your router.ex or endpoint.ex
plug TenantPlug,
  sources: [
    TenantPlug.Sources.FromHeader,
    TenantPlug.Sources.FromSubdomain
  ]
```

### 2. Access tenant context in your application

```elixir
# In controllers, contexts, or anywhere in your app
defmodule MyApp.UserController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    case TenantPlug.current() do
      nil -> 
        conn |> put_status(400) |> json(%{error: "Tenant required"})
      
      tenant_id ->
        users = MyApp.Users.list_users_for_tenant(tenant_id)
        json(conn, users)
    end
  end
end
```

### 3. Use in background jobs

```elixir
# Capture context when enqueuing job
def enqueue_report_job do
  snapshot = TenantPlug.snapshot()
  MyApp.ReportWorker.new(%{tenant_snapshot: snapshot, type: "monthly"})
end

# Apply context in worker
defmodule MyApp.ReportWorker do
  use Oban.Worker

  def perform(%{args: %{"tenant_snapshot" => snapshot} = args}) do
    TenantPlug.apply_snapshot(snapshot)
    
    # Now TenantPlug.current() works in this process
    tenant_id = TenantPlug.current()
    generate_report(tenant_id, args["type"])
  end
end
```

## Configuration Options

```elixir
plug TenantPlug,
  sources: [
    # Extract from HTTP header (default: "x-tenant-id")
    {TenantPlug.Sources.FromHeader, header: "x-tenant-id"},
    
    # Extract from subdomain
    {TenantPlug.Sources.FromSubdomain, exclude_subdomains: ["www", "api"]},
    
    # Extract from JWT claims
    {TenantPlug.Sources.FromJWT, claim: "tenant_id", verifier: MyApp.JWT}
  ],
  
  # Process dictionary key (default: :tenant_plug_tenant)
  key: :tenant_plug_tenant,
  
  # Enable Logger metadata (default: true)
  logger_metadata: true,
  
  # Enable telemetry events (default: true)
  telemetry: true,
  
  # Require tenant to be resolved (default: false)
  require_resolved: false,
  
  # Custom handler when tenant required but missing
  on_missing: &MyApp.Auth.handle_missing_tenant/1
```

## Built-in Sources

### FromHeader
Extracts tenant from HTTP headers.

```elixir
{TenantPlug.Sources.FromHeader, 
  header: "x-tenant-id",
  mapper: &String.upcase/1  # Optional transformation
}
```

### FromSubdomain
Extracts tenant from request subdomain.

```elixir
{TenantPlug.Sources.FromSubdomain,
  host_split_index: 0,  # Which part to extract (0 = first)
  exclude_subdomains: ["www", "api", "admin"]
}
```

### FromJWT
Extracts tenant from JWT token claims.

```elixir
{TenantPlug.Sources.FromJWT,
  claim: "tenant_id",
  verifier: MyApp.JWT,  # Module or function that verifies JWT
  header: "authorization"  # Header containing token (default)
}
```

## Testing

Use the provided test helpers for easy testing:

```elixir
defmodule MyApp.UserControllerTest do
  use MyAppWeb.ConnCase
  import TenantPlug.TestHelpers

  setup do
    # Set tenant context for each test
    set_current("test_tenant")
    on_exit(fn -> clear_current() end)
  end

  test "lists users for current tenant", %{conn: conn} do
    conn = get(conn, "/api/users")
    assert json_response(conn, 200)
  end

  test "temporarily use different tenant" do
    with_tenant("other_tenant", fn ->
      assert TenantPlug.current() == "other_tenant"
      # Test tenant-specific behavior
    end)
    
    # Back to original tenant
    assert TenantPlug.current() == "test_tenant"
  end
end
```

## Telemetry Events

TenantPlug emits the following telemetry events:

- `[:tenant_plug, :tenant, :resolved]` - When tenant is successfully extracted
- `[:tenant_plug, :tenant, :cleared]` - When tenant context is cleared
- `[:tenant_plug, :error, :source_exception]` - When a source raises an exception

Example telemetry handler:

```elixir
:telemetry.attach(
  "tenant-metrics",
  [:tenant_plug, :tenant, :resolved],
  fn _event, _measurements, metadata, _config ->
    MyMetrics.increment("tenant.resolved", tags: %{
      source: metadata.source,
      tenant: metadata.tenant_snapshot
    })
  end,
  nil
)
```

## Custom Sources

Create custom extraction sources by implementing the behaviour:

```elixir
defmodule MyApp.TenantSources.FromCookie do
  @behaviour TenantPlug.Sources.Behaviour

  def extract(conn, opts) do
    cookie_name = Map.get(opts, :cookie, "tenant_id")
    
    case conn.req_cookies[cookie_name] do
      nil -> :error
      tenant_id -> {:ok, tenant_id, %{source: :cookie, raw: tenant_id}}
    end
  end
end

# Use in your plug configuration
plug TenantPlug,
  sources: [MyApp.TenantSources.FromCookie]
```

## Architecture

TenantPlug follows these design principles:

- **Minimal and focused**: Only handles tenant context, not data access or authorization
- **Process-local storage**: Uses `Process.put/get` for fast, isolated context
- **Pluggable sources**: Easy to extend with custom extraction strategies
- **Observable**: Comprehensive logging and telemetry integration
- **Test-friendly**: Dedicated helpers for testing tenant-scoped code

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`mix test`)
4. Commit your changes (`git commit -am 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## Roadmap

TenantPlug focuses on context management. For a complete multi-tenant solution, consider these complementary libraries:

- **tenant_ecto** - Automatic Ecto query scoping (planned)
- **tenant_cache** - Tenant-aware caching (planned)
- **tenant_db** - Database provisioning and migrations (planned)

