# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TenantPlug is an Elixir library for automatic tenant context management in Phoenix applications. It extracts tenant information from configurable sources (subdomain, headers, JWT) and provides process-local context storage with utilities for accessing tenant information throughout applications.

## Development Commands

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix test --cover

# Format code
mix format

# Generate documentation
mix docs

# Type checking (if dialyzer is added)
mix dialyzer

# Compile
mix compile
```

## Architecture

### Core Components

- **TenantPlug** (`lib/tenant_plug.ex`) - Main plug module that orchestrates tenant extraction and context management
- **TenantPlug.Context** (`lib/tenant_plug/context.ex`) - Process-local storage using `Process.put/get` for tenant context and snapshot functionality
- **Source modules** (`lib/tenant_plug/sources/`) - Pluggable extraction strategies implementing `TenantPlug.Sources.Behaviour`
- **TenantPlug.Logger** (`lib/tenant_plug/logger.ex`) - Logger metadata integration for observability
- **TenantPlug.Telemetry** (`lib/tenant_plug/telemetry.ex`) - Telemetry events for monitoring
- **TenantPlug.TestHelpers** (`lib/tenant_plug/test_helpers.ex`) - Testing utilities

### Built-in Sources

- `FromSubdomain` - Extracts tenant from request subdomain (default source)
- `FromHeader` - Extracts from HTTP headers (e.g., "x-tenant-id")  
- `FromJWT` - Extracts from JWT token claims

### Key Design Patterns

- **Pluggable architecture**: Sources implement behaviour for custom extraction strategies
- **Process-local context**: Fast, isolated tenant storage using Process dictionary
- **Snapshot/restore**: Serializable context for background jobs and cross-process tenant propagation
- **Fail-safe source chain**: Multiple sources tried in order, first success wins
- **Optional requirements**: Can require tenant resolution or allow requests without tenant

### Testing Approach

- Tests are in `test/` directory organized by module
- Uses `TenantPlug.TestHelpers` for context management in tests
- Integration tests verify full plug behavior
- Performance tests ensure minimal overhead
- Error handling tests verify graceful failures

### Key Configuration Options

- `:sources` - List of extraction sources to try in order
- `:key` - Process dictionary key for storage (default: `:tenant_plug_tenant`)
- `:require_resolved` - Whether to halt requests without tenant
- `:logger_metadata` / `:telemetry` - Observability toggles
- `:on_missing` - Custom handler for missing tenant scenarios