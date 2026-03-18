# API Documentation Template

Use this template to document an internal library, module, or package. Fill in each section. Remove sections that do not apply, but err on the side of including them -- missing documentation is worse than redundant documentation.

---

## Module Overview

### Name

`<package-name>` (e.g., `@acme/http-client`, `acme.auth`, `acme::cache`)

### Purpose

<!-- One paragraph: What does this library do? What problem does it solve? Why does it exist instead of using an off-the-shelf solution? -->

### Installation / Import

```
# Package manager install (if applicable)
npm install @acme/package-name
pip install acme-package-name
```

```typescript
// Import statement
import { createClient, ClientConfig } from '@acme/package-name'
```

### Quick Start

```typescript
// Minimal working example -- the fewest lines to get something useful running.
// Include all required setup (env vars, initialization) so this example works in isolation.

const client = createClient({
  baseUrl: process.env.API_BASE_URL,
})

const result = await client.get('/users/me')
```

### Requirements

| Requirement | Value | Notes |
|-------------|-------|-------|
| Runtime | Node.js >= 18 | Uses native `fetch` |
| Peer dependencies | `@acme/logger >= 2.0` | Must be installed separately |
| Environment variables | See Configuration section | `API_BASE_URL` is required |

---

## API Reference

### Exports Summary

| Export | Type | Description |
|--------|------|-------------|
| `createClient` | Function | Factory function to create a configured client instance |
| `ClientConfig` | Type/Interface | Configuration options for `createClient` |
| `Client` | Class | The client instance returned by `createClient` |
| `ApiResponse<T>` | Type/Interface | Standard response wrapper type |
| `ClientError` | Class | Base error class for all client errors |
| `DEFAULT_TIMEOUT` | Constant | Default timeout value (5000ms) |

---

## Detailed Function Documentation

### `createClient(config)`

**Description:** Creates and returns a configured client instance. Call this once at application startup and reuse the returned instance.

**Signature:**

```typescript
function createClient(config: ClientConfig): Client
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `config` | `ClientConfig` | Yes | -- | Client configuration object |
| `config.baseUrl` | `string` | Yes | -- | Base URL for all requests. Must include protocol. |
| `config.timeout` | `number` | No | `5000` | Request timeout in milliseconds. `0` disables timeout. |
| `config.retryPolicy` | `RetryPolicy` | No | `{ maxRetries: 3, backoff: 'exponential' }` | Retry configuration for failed requests |
| `config.auth` | `AuthConfig \| undefined` | No | `undefined` | Authentication configuration. Omit for unauthenticated requests. |
| `config.headers` | `Record<string, string>` | No | `{}` | Default headers applied to every request |

**Returns:** `Client` -- A configured client instance. This instance is stateful (maintains connection pool, auth tokens) and should be reused.

**Errors:**

| Error | Condition | Recovery |
|-------|-----------|----------|
| `ConfigError` | `baseUrl` is missing or malformed | Provide a valid URL including protocol (`https://...`) |
| `ConfigError` | `timeout` is negative | Use `0` to disable timeout, or a positive integer |

**Example (basic):**

```typescript
const client = createClient({
  baseUrl: 'https://api.internal.acme.com',
})
```

**Example (fully configured):**

```typescript
const client = createClient({
  baseUrl: process.env.API_BASE_URL,
  timeout: 10000,
  retryPolicy: { maxRetries: 2, backoff: 'linear' },
  auth: {
    type: 'bearer',
    tokenProvider: () => getServiceToken(),
  },
  headers: {
    'X-Service-Name': 'my-service',
  },
})
```

---

### `client.get<T>(url, options?)`

<!-- Repeat this block for each function. Copy the structure above. -->

**Description:** <!-- What it does -->

**Signature:**

```typescript
function get<T>(url: string, options?: RequestOptions): Promise<ApiResponse<T>>
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `url` | `string` | Yes | -- | <!-- Description --> |
| `options` | `RequestOptions` | No | `{}` | <!-- Description --> |

**Returns:** `Promise<ApiResponse<T>>` -- <!-- Description of return value shape -->

**Errors:**

| Error | Condition | Recovery |
|-------|-----------|----------|
| <!-- Error type --> | <!-- When it occurs --> | <!-- How to fix --> |

**Example (happy path):**

```typescript
// Show the simplest correct invocation
```

**Example (error handling):**

```typescript
// Show proper error handling pattern
try {
  const response = await client.get<User>('/users/me')
  return response.data
} catch (error) {
  if (error instanceof TimeoutError) {
    // Handle timeout specifically
  }
  throw error
}
```

---

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `API_BASE_URL` | Yes | -- | Base URL for the API. Must include protocol. |
| `API_TIMEOUT` | No | `5000` | Default timeout in milliseconds |
| `API_MAX_RETRIES` | No | `3` | Maximum retry attempts for failed requests |
| `API_LOG_LEVEL` | No | `warn` | Logging verbosity: `debug`, `info`, `warn`, `error`, `silent` |

### Config File Options

<!-- If the library reads from a config file, document its schema here. -->

```yaml
# config/http-client.yaml
baseUrl: https://api.internal.acme.com
timeout: 5000
retryPolicy:
  maxRetries: 3
  backoff: exponential
  baseDelay: 1000
```

### Configuration Precedence

When the same option is specified in multiple places, the following precedence applies (highest to lowest):

1. Runtime parameter passed to function call
2. Constructor/factory configuration object
3. Environment variable
4. Config file value
5. Library default

---

## Common Patterns

### Pattern 1: Singleton Client with Dependency Injection

```typescript
// services/http.ts -- Create once, import everywhere
import { createClient } from '@acme/http-client'

export const httpClient = createClient({
  baseUrl: process.env.API_BASE_URL,
  auth: {
    type: 'bearer',
    tokenProvider: () => getServiceToken(),
  },
})

// routes/users.ts -- Import the singleton
import { httpClient } from '../services/http'

export async function getUser(id: string) {
  const response = await httpClient.get<User>(`/users/${id}`)
  return response.data
}
```

### Pattern 2: Request-Scoped Configuration Override

```typescript
// Override defaults for a specific request without mutating the client
const response = await client.get<LargeReport>('/reports/annual', {
  timeout: 30000, // Override default timeout for slow endpoint
  headers: {
    'Accept-Encoding': 'gzip',
  },
})
```

### Pattern 3: Error Handling with Fallback

```typescript
import { NetworkError, TimeoutError } from '@acme/http-client'

async function getUserWithFallback(id: string): Promise<User> {
  try {
    const response = await primaryClient.get<User>(`/users/${id}`)
    return response.data
  } catch (error) {
    if (error instanceof NetworkError || error instanceof TimeoutError) {
      const cached = await cache.get(`user:${id}`)
      if (cached) {
        return cached
      }
    }
    throw error
  }
}
```

---

## Migration Guide

### Migrating from v2 to v3

<!-- Document breaking changes and how to update consumer code. -->

#### Breaking Changes

| Change | v2 Behavior | v3 Behavior | Migration |
|--------|-------------|-------------|-----------|
| `createClient` return type | Returns raw client | Returns wrapped client | Update type annotations |
| Retry default | Retries all methods | Retries only GET/HEAD | Pass `retryPolicy.methods: ['GET', 'HEAD', 'POST']` to restore old behavior |
| Error types | Generic `Error` | Specific `ClientError` subtypes | Update `catch` blocks to handle new types |

#### Step-by-Step Migration

1. Update the package version in your manifest
2. Search for all `createClient` call sites
3. Update error handling to use new error types
4. Test retry behavior for non-GET requests
5. Run integration tests against staging

#### Compatibility Mode

```typescript
// Temporary compatibility: restore v2 retry behavior
const client = createClient({
  ...existingConfig,
  retryPolicy: {
    ...existingConfig.retryPolicy,
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'],
  },
})
```

---

## Known Limitations

<!-- List things this library cannot do, does not handle well, or has known issues with. -->

- **No streaming support.** Responses are fully buffered in memory. Do not use for large file downloads.
- **Connection pool is per-client.** Creating multiple client instances multiplies connection pool usage. Prefer singletons.
- **No WebSocket support.** Use `@acme/ws-client` for WebSocket connections.
- **Retry logic does not deduplicate.** If a request times out but the server processed it, retrying may cause duplicates for non-idempotent operations.
- **Auth token refresh is synchronous.** Concurrent requests during token refresh will queue, potentially causing latency spikes.

---

## Changelog

### v3.1.0 (2026-02-15)

- Added `AbortController` support for request cancellation
- Fixed connection pool leak when requests are cancelled mid-flight

### v3.0.0 (2026-01-10)

- **Breaking:** Retry logic no longer retries POST/PUT/PATCH/DELETE by default
- **Breaking:** Error types changed from generic `Error` to specific subtypes
- Added `ClientError.code` field for programmatic error handling
- Improved timeout accuracy using `AbortSignal.timeout()`

### v2.4.0 (2025-11-20)

- Added `X-Request-ID` header to all outgoing requests
- Fixed race condition in auth token refresh

---

## Appendix: Type Definitions

<!-- Include the full type definitions for complex types referenced above. -->

```typescript
interface ClientConfig {
  baseUrl: string
  timeout?: number
  retryPolicy?: RetryPolicy
  auth?: AuthConfig
  headers?: Record<string, string>
}

interface RetryPolicy {
  maxRetries: number
  backoff: 'linear' | 'exponential' | 'none'
  baseDelay?: number
  methods?: string[]
}

interface AuthConfig {
  type: 'bearer' | 'basic' | 'custom'
  tokenProvider?: () => string | Promise<string>
  username?: string
  password?: string
  headerName?: string
  headerValuePrefix?: string
}

interface ApiResponse<T> {
  data: T
  status: number
  headers: Record<string, string>
  duration: number
}

class ClientError extends Error {
  code: string
  status?: number
  cause?: Error
}

class NetworkError extends ClientError {
  code: 'NETWORK_ERROR'
}

class TimeoutError extends ClientError {
  code: 'TIMEOUT'
  timeoutMs: number
}

class ConfigError extends ClientError {
  code: 'CONFIG_ERROR'
  field: string
}
```
