# Common Library Gotchas

A categorized reference of issues that frequently arise when working with internal libraries. Use this as a checklist when investigating library behavior, onboarding to unfamiliar code, or documenting known pitfalls.

---

## 1. Initialization & Lifecycle

Internal libraries often have implicit startup and shutdown requirements that are not obvious from their API signatures.

### Module-Level Side Effects

**Problem:** The library executes code at import time -- establishing connections, reading config files, or registering global handlers. Importing the library in a test file or a script that does not have the required environment triggers unexpected errors.

**Mitigation:** Search for top-level function calls, `await` statements, and constructor invocations outside of exported functions. Wrap side effects in explicit `init()` functions that consumers call deliberately.

### Singleton State Leaks Across Contexts

**Problem:** A library exports a singleton instance (e.g., a pre-configured client or connection pool). In monorepos or test suites, multiple consumers share this singleton, and one consumer's configuration or state changes affect all others.

**Mitigation:** Prefer factory functions (`createClient()`) over exported singletons. If singletons are necessary, provide a `reset()` or `destroy()` method for test isolation.

### Lazy Initialization Race Conditions

**Problem:** The library initializes lazily on first use. When multiple concurrent callers trigger initialization simultaneously, the library may initialize multiple times, create duplicate connections, or enter an inconsistent state.

**Mitigation:** Use a synchronization primitive (mutex, `once` pattern, or a pending-promise cache) to ensure initialization runs exactly once regardless of concurrent callers.

### Missing Cleanup and Disposal

**Problem:** The library acquires resources (connections, file handles, timers, event listeners) but does not expose a `close()`, `destroy()`, or `dispose()` method. Consumers cannot release resources gracefully, leading to leaks in long-running processes or test suites.

**Mitigation:** Document the cleanup contract. If the library lacks cleanup, wrap it in a higher-level abstraction that manages the lifecycle.

### Initialization Order Dependencies

**Problem:** Library A must be initialized before Library B because B reads state that A sets up (e.g., a logger that must be configured before the HTTP client captures it). This ordering constraint is undocumented and breaks when code is reorganized.

**Mitigation:** Make dependencies explicit via parameters rather than global state. If ordering is unavoidable, document it prominently and add runtime checks that fail fast with clear error messages.

---

## 2. Configuration

Configuration-related gotchas are among the most common causes of "works on my machine" failures.

### Environment Variable Coupling

**Problem:** The library reads environment variables directly from `process.env` / `os.environ` at import time or at arbitrary points during execution. Consumers cannot override these values programmatically, and changes to env vars after import have no effect.

**Mitigation:** Accept configuration via constructor parameters or options objects with env vars as fallback defaults. Read env vars once and store the result, making the read time explicit and predictable.

### Config Precedence Confusion

**Problem:** The library accepts configuration from multiple sources (env vars, config files, constructor parameters, defaults) but the precedence order is undocumented. Consumers set a value in one place and it is silently overridden by another source.

**Mitigation:** Document the precedence order explicitly. Log the resolved configuration at startup (at debug level) so consumers can verify which values are in effect.

### Defaults That Differ Between Environments

**Problem:** Default values that are reasonable in development are wrong in production. A default timeout of 30 seconds is fine locally but causes cascading failures under load. A default log level of `debug` floods production logging infrastructure.

**Mitigation:** Make defaults conservative (short timeouts, minimal logging) and document which defaults should be overridden per environment. Consider supporting environment-aware defaults (`NODE_ENV`-based) with clear documentation.

### Config Validation Happens Too Late

**Problem:** The library accepts invalid configuration silently at construction time and only fails when the misconfigured code path is exercised -- potentially hours or days later in production.

**Mitigation:** Validate all configuration eagerly at construction time. Throw clear errors with the specific field name, expected format, and actual value received.

### Sensitive Config in Error Messages

**Problem:** When configuration validation fails, the error message includes the raw configuration value -- which may be an API key, password, or connection string. This value then appears in logs, error tracking systems, and crash reports.

**Mitigation:** Never include raw secret values in error messages. Log the config key name, expected format, and a redacted preview (e.g., `sk-proj-...xxxx`).

---

## 3. Type Safety

Type definitions provide a false sense of security when they do not accurately represent runtime behavior.

### Runtime/Type Mismatch

**Problem:** The TypeScript types say a function returns `User`, but at runtime it returns `User | null`, `User | undefined`, or a differently-shaped object. This happens when types were written optimistically, when the API evolved without updating types, or when types were auto-generated from an outdated schema.

**Mitigation:** When documenting a library, always verify type claims against actual usage in tests and call sites. Use runtime validation (Zod, io-ts) at trust boundaries.

### Generic Type Erasure in Error Paths

**Problem:** A generic function `get<T>(url): Promise<T>` correctly types the happy path, but errors are untyped or typed as `unknown`. Callers cannot distinguish between error types without runtime checks that the types do not help with.

**Mitigation:** Define explicit error types and use discriminated unions or error codes. Document which errors each function can throw and their types.

### Union Type Narrowing Gaps

**Problem:** A function returns `Result | Error` or `Success | Failure`, but the narrowing logic (type guards) is incomplete or incorrect. Code that appears to handle all cases at the type level misses a runtime variant.

**Mitigation:** Prefer discriminated unions with a `type` or `kind` field. Add exhaustiveness checks (`assertNever` patterns) at compile time.

### Overloaded Signatures That Mislead

**Problem:** A function has multiple overloaded signatures for developer convenience, but the implementation handles only some overloads correctly. The least-used overload is the one most likely to be buggy.

**Mitigation:** Test each overload independently. When documenting, note which overloads are well-tested and which are edge cases.

---

## 4. Dependencies

Dependency issues compound in internal libraries because they lack the community scrutiny that open-source packages receive.

### Circular Dependencies

**Problem:** Library A imports from Library B, and Library B imports from Library A (directly or transitively). At runtime, one of the imports resolves to `undefined` or a partially-initialized module, causing cryptic errors like "Cannot read property 'x' of undefined."

**Mitigation:** Use dependency visualization tools (`madge` for JS, import graph analyzers). Break cycles by extracting shared types/interfaces into a separate package or using dependency inversion.

### Version Drift Across Consumers

**Problem:** Multiple services consume the same internal library but pin different versions. A bug fix in v2.3.1 is available in some services but not others. Documentation refers to the latest version, confusing developers on older versions.

**Mitigation:** Use a monorepo with unified versioning, or maintain a compatibility matrix. When documenting, note which version introduced each feature or fix.

### Peer Dependency Conflicts

**Problem:** The library declares a peer dependency on a specific version range, but the consumer's dependency tree includes an incompatible version. This causes duplicate instances of the peer dependency, leading to `instanceof` checks failing, duplicate state, or subtle behavioral differences.

**Mitigation:** Keep peer dependency ranges as wide as possible. Test against the minimum and maximum supported versions. Document exact peer dependency requirements prominently.

### Implicit Globals and Polyfills

**Problem:** The library assumes certain globals exist (`fetch`, `AbortController`, `crypto`, `Buffer`) without declaring a dependency on a polyfill. It works in Node.js 18+ but fails in Node.js 16, or works in the browser but fails in SSR contexts.

**Mitigation:** Document the minimum runtime version and required globals. Either bundle polyfills or fail fast with a clear message when a required global is missing.

### Transitive Dependency Vulnerabilities

**Problem:** The library depends on a package with a known vulnerability. Because it is an internal library, automated vulnerability scanning may not cover it the same way it covers direct dependencies.

**Mitigation:** Include internal libraries in vulnerability scanning pipelines. Pin transitive dependencies and audit them during updates.

---

## 5. Error Handling

Error handling in internal libraries is frequently inconsistent because different authors contribute over time without a unified strategy.

### Swallowed Errors

**Problem:** The library catches errors internally and returns a default value, logs a warning, or silently continues. The caller has no way to detect or handle the failure. This is especially dangerous in fire-and-forget operations (analytics, logging, cache writes).

**Mitigation:** Search for empty `catch` blocks, `catch` blocks that only log, and `.catch(() => {})` patterns. Document which operations can silently fail and whether the library provides a way to register error callbacks.

### Error Type Inconsistency

**Problem:** The library sometimes throws `Error`, sometimes returns an error object, sometimes rejects a promise, and sometimes calls an error callback. The error handling contract varies by function or even by code path within the same function.

**Mitigation:** Document the error contract for each function. Prefer a consistent pattern across the library (e.g., always throw, or always return Result types).

### Missing Error Codes

**Problem:** Errors thrown by the library have descriptive messages but no machine-readable error code. Callers resort to string-matching on error messages to determine the error type, which breaks when messages are reworded.

**Mitigation:** Add an `error.code` field to all custom errors. Document error codes and their meanings. Never rely on error message text for programmatic decisions.

### Retry-Unsafe Operations Masked as Retryable

**Problem:** The library wraps operations in retry logic without distinguishing between idempotent and non-idempotent operations. A failed POST that was actually processed by the server gets retried, creating duplicates.

**Mitigation:** Document which operations are safe to retry. Provide an `idempotencyKey` option for operations that support server-side deduplication. Default to not retrying non-GET requests.

### Errors That Lose Context

**Problem:** The library catches a low-level error and throws a new high-level error without attaching the original error as a `cause`. The stack trace and details of the root cause are lost, making debugging difficult.

**Mitigation:** Always use the `cause` property (or language equivalent) when wrapping errors. Preserve the original stack trace and error details.

---

## 6. Performance

Performance gotchas in internal libraries are subtle because they only manifest under load or at scale.

### Hidden N+1 Patterns

**Problem:** A convenience method fetches a list of items, then makes an individual request for each item to enrich it with additional data. With 10 items this is fine; with 1,000 items this saturates the network or database.

**Mitigation:** Search for loops containing async calls, `.map()` with `await` inside, or sequential promise resolution. Document batch alternatives when they exist.

### Unbounded Caches

**Problem:** The library caches results in a `Map` or plain object without a size limit or TTL. Over time, the cache grows without bound, consuming increasing amounts of memory.

**Mitigation:** Look for `Map` or object-based caches that lack eviction logic. Document the cache behavior and recommend configuring max size and TTL for production use.

### Synchronous Operations Blocking the Event Loop

**Problem:** The library performs CPU-intensive or I/O-synchronous operations on the main thread -- JSON parsing of large payloads, synchronous file reads, or cryptographic operations. This blocks the event loop and degrades throughput for all concurrent requests.

**Mitigation:** Search for `readFileSync`, `JSON.parse` on unbounded input, and synchronous crypto operations. Document which operations are blocking and suggest async alternatives.

### Connection Pool Exhaustion

**Problem:** The library creates a connection pool of fixed size. Under high concurrency, all connections are in use and new requests queue indefinitely or time out. The default pool size may be appropriate for development but too small for production.

**Mitigation:** Document the default pool size and how to configure it. Add monitoring for pool utilization. Set a queue timeout so callers fail fast rather than hanging.

### Memory Leaks from Event Listeners

**Problem:** The library registers event listeners (on sockets, streams, or EventEmitters) but does not remove them on cleanup. In long-running processes, listener counts grow until the process runs out of memory or Node.js emits a `MaxListenersExceeded` warning.

**Mitigation:** Audit listener registration and removal. Ensure every `on()` / `addEventListener()` has a corresponding `off()` / `removeEventListener()` in the cleanup path.

---

## 7. Testing

Testing internal libraries is harder than testing application code because libraries are designed to be used in diverse contexts.

### Mocking Difficulties

**Problem:** The library's internal structure is tightly coupled, making it difficult to mock dependencies for unit testing. Consumers who want to mock the library in their own tests find that it does not expose interfaces or injection points.

**Mitigation:** Export interfaces alongside implementations. Use dependency injection for external services (HTTP, database, filesystem). Document the recommended mocking strategy for consumers.

### Global State Leakage Between Tests

**Problem:** Tests pass individually but fail when run together. The library maintains global state (singleton instances, module-level variables, registered handlers) that leaks between test cases. Test order matters, and parallel test execution is impossible.

**Mitigation:** Provide `reset()` or `destroy()` functions for test use. Avoid module-level mutable state. If global state is unavoidable, document the cleanup procedure for test suites.

### Time-Dependent Behavior

**Problem:** The library uses `Date.now()`, `setTimeout`, or system clocks internally. Tests that depend on timing are flaky, and behaviors like token expiration, cache TTL, and rate limiting are difficult to test deterministically.

**Mitigation:** Accept a clock/timer abstraction as a configuration option. In tests, inject a fake clock that can be advanced manually. Document time-dependent behavior and how to test it.

### Test Fixtures That Encode Assumptions

**Problem:** Test fixtures contain hardcoded data (URLs, IDs, timestamps) that encode assumptions about the test environment. When the environment changes, tests fail for non-obvious reasons.

**Mitigation:** Generate test data dynamically using factories or builders. Document which fixtures are environment-dependent and how to update them.

### Integration Tests That Require Infrastructure

**Problem:** The library's test suite requires a running database, message queue, or external service. Contributors cannot run tests without setting up the full infrastructure stack, reducing the likelihood that tests are run during development.

**Mitigation:** Use test containers, in-memory implementations, or recorded HTTP responses (e.g., `nock`, `VCR`) for integration tests. Document the test infrastructure requirements and provide a single-command setup.
