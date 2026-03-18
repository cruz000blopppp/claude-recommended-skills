# Code Review Rubric

Detailed checklist for each review pass. Use this as a reference during reviews — not every item applies to every review. Focus on items relevant to the changed code.

---

## Pass 1: Structural Review

### Checklist

1. **File size**: Is the file under 400 lines? Flag if over 400, hard flag if over 800.
2. **Function size**: Are all functions under 50 lines? Can long functions be decomposed into named steps?
3. **Nesting depth**: Is nesting kept to 4 levels or fewer? Are early returns used to flatten logic?
4. **Naming clarity**: Do names describe what, not how? Are abbreviations avoided unless universally understood?
5. **Single responsibility**: Does each file/module/class have one clear reason to change?
6. **Co-location**: Are related files grouped by feature or domain, not by type (e.g., not all controllers in one folder)?
7. **Export surface**: Are only necessary symbols exported? Are internal helpers kept private?
8. **Dead code**: Are there commented-out blocks, unused imports, or unreachable branches?
9. **Consistent structure**: Do similar files follow the same internal layout (imports, types, constants, logic, exports)?
10. **Import hygiene**: Are imports organized and free of circular dependencies?

### PASS Criteria

- Files are focused and appropriately sized.
- Names communicate intent without needing comments to explain them.
- Each function does one thing at one level of abstraction.
- The file can be understood by reading top to bottom without jumping around.

### FAIL Criteria

- A file exceeds 800 lines with no clear justification.
- A function exceeds 50 lines and mixes abstraction levels.
- Nesting exceeds 4 levels without extraction.
- Names are misleading (e.g., `process()` that also validates and saves).
- Dead code is left without explanation.

### Example Findings

| Severity | Finding |
|----------|---------|
| HIGH | `services/payment.ts` is 1,200 lines. Extract refund logic, webhook handling, and receipt generation into separate modules. |
| MEDIUM | `handleOrder()` is 78 lines with 5 levels of nesting. Consider early returns and extracting the discount calculation. |
| LOW | `data` is used as a variable name in 3 places with different meanings. More specific names would reduce cognitive load. |
| NIT | Imports are not grouped consistently — third-party and local imports are mixed. |

### What NOT to Flag

- File length between 400-800 lines if the file is highly cohesive and splitting would create artificial boundaries.
- Short temporary variable names in tight scopes (e.g., `i` in a 3-line loop, `e` in a catch block).
- Generated files, migration files, or configuration files that are long by nature.
- Barrel files (`index.ts` re-exports) that exist purely for import convenience.

---

## Pass 2: Logic Review

### Checklist

1. **Happy path correctness**: Does the core logic produce the right result for standard inputs?
2. **Null/undefined handling**: Are nullable values checked before access? Are optional chains used appropriately?
3. **Empty collection handling**: Does the code handle empty arrays, empty strings, empty objects?
4. **Boundary values**: Are zero, negative numbers, max integers, and unicode strings handled?
5. **Error handling**: Are errors caught with sufficient context? Are they re-thrown or handled — not swallowed?
6. **Input validation**: Is user input validated at the boundary? Are schemas used where appropriate?
7. **Async correctness**: Are promises awaited? Are race conditions between async operations prevented?
8. **Resource cleanup**: Are connections, listeners, timers, and file handles cleaned up in all paths (including error paths)?
9. **Comparison correctness**: Is strict equality used? Are comparisons between different types avoided?
10. **Loop termination**: Do all loops have clear termination conditions? Are infinite loops guarded?
11. **State transitions**: Are state changes valid? Can invalid states be represented?
12. **Idempotency**: If this operation runs twice, does it produce the same result or cause problems?

### PASS Criteria

- All code paths (success, error, edge case) are handled intentionally.
- Errors include enough context to diagnose issues in production.
- User input is never trusted — validated before processing.
- Async operations are correctly sequenced with proper error handling.

### FAIL Criteria

- A thrown error is caught and silently ignored (empty catch block).
- User input flows directly into database queries, file operations, or shell commands.
- An async function is called without `await` and its rejection is unhandled.
- A nullable value is accessed without a check, and the type system doesn't prevent it.

### Example Findings

| Severity | Finding |
|----------|---------|
| CRITICAL | `req.query.id` is interpolated directly into a SQL query string at `db.ts:45`. Use parameterized queries. |
| HIGH | `processPayment()` catches all errors and returns `null`. The caller has no way to distinguish "not found" from "network failure." |
| MEDIUM | `users.find()` result is used without null check at `roster.ts:112`. If no user matches, the next line throws `Cannot read property 'name' of undefined`. |
| LOW | The `for` loop at `batch.ts:30` could use `for...of` for clarity since the index is only used to access the element. |

### What NOT to Flag

- Defensive checks that the type system already guarantees (e.g., null check on a non-nullable type with strict mode on).
- Missing error handling in test files or scripts that are meant to fail loudly.
- Performance of operations that run once at startup or on tiny datasets.
- Edge cases that are explicitly out of scope per the PR description or ticket.

---

## Pass 3: Convention Review

### Checklist

1. **Immutability**: Are objects and arrays created via spread/map/filter rather than mutated via push/splice/direct assignment?
2. **Error pattern consistency**: Do new error handling patterns match the existing codebase convention?
3. **Type definitions**: Are interfaces/types defined and used? Are `any` casts justified with a comment?
4. **Constant extraction**: Are magic numbers and strings extracted into named constants?
5. **Console cleanup**: Are `console.log` debugging statements removed?
6. **API response shape**: Do new endpoints return the standard response format?
7. **Import conventions**: Do imports follow the project's ordering and grouping rules?
8. **Naming conventions**: Do names follow the codebase pattern (camelCase, PascalCase, UPPER_SNAKE_CASE for constants)?
9. **File naming**: Do file names match the project convention (kebab-case, camelCase, etc.)?
10. **Comment quality**: Are comments explaining "why," not "what"? Are JSDoc/TSDoc used where the project requires them?

### PASS Criteria

- New code is indistinguishable in style from existing code in the same module.
- Team conventions are followed without exception or are accompanied by justification.
- No debugging artifacts remain in the code.
- Types are used consistently and narrowly.

### FAIL Criteria

- Objects are mutated when the codebase consistently uses immutable patterns.
- `any` is used without a comment explaining why a proper type cannot be defined.
- `console.log` statements are left in production code paths.
- A new API endpoint returns a different shape than all existing endpoints.

### Example Findings

| Severity | Finding |
|----------|---------|
| HIGH | `updateUser()` at `user-service.ts:67` mutates the input parameter directly. The codebase uses immutable patterns — return a new object via spread instead. |
| MEDIUM | `MAX_RETRIES = 3` is hardcoded at `api-client.ts:12`. Extract to a named constant or config value. |
| LOW | `console.log('debug')` at `auth.ts:44` — remove before merge. |
| NIT | Imports at `dashboard.tsx:1-8` mix third-party and local imports without a blank line separator. |

### What NOT to Flag

- Convention deviations in legacy files that are not being modified in this change.
- Minor import ordering differences when the project has no enforced convention.
- Style differences in test files when the team has explicitly relaxed test conventions.
- Code that follows a different convention because it interfaces with an external library that uses that convention (e.g., callback-style for a callback-based API).

---

## Pass 4: Architecture Review

### Checklist

1. **Module coupling**: Does this change increase dependencies between modules that should be independent?
2. **Cohesion**: Does each module contain only logically related functionality?
3. **Abstraction timing**: Is a new abstraction being introduced too early (YAGNI) or too late (duplication is already widespread)?
4. **Circular dependencies**: Does the import graph introduce or worsen cycles?
5. **Dependency direction**: Do dependencies flow from concrete to abstract, from feature to utility?
6. **API surface expansion**: Does this change add to the public API? Is the expansion intentional and documented?
7. **Layer violations**: Does this bypass an established architectural layer (e.g., UI component calling the database directly)?
8. **Pattern consistency**: If the codebase uses established patterns (Repository, Observer, Factory), does new code follow them?
9. **Extensibility**: If this feature will likely grow, is the current structure accommodating or constraining?
10. **Testability**: Can this code be tested in isolation, or does it require complex setup that indicates tight coupling?

### PASS Criteria

- New code follows established architectural patterns in the codebase.
- Module boundaries are respected — no reaching across layers.
- Abstractions exist because they solve a real problem, not a hypothetical one.
- The change could be understood and modified without deep knowledge of unrelated modules.

### FAIL Criteria

- A new direct dependency is created between modules that previously communicated through an interface.
- A utility module imports a feature module, inverting the dependency direction.
- An abstraction is introduced for a single use case with no evidence of reuse.
- The change requires modifying 5+ unrelated files, suggesting a coupling problem.

### Example Findings

| Severity | Finding |
|----------|---------|
| CRITICAL | `PaymentService` now imports `UserProfileComponent`. A service should never depend on a UI component — extract the shared logic into a domain module. |
| HIGH | `utils/formatting.ts` now imports from `features/billing/`. Utility modules should not depend on feature modules. Move the shared function or invert the dependency. |
| MEDIUM | `createOrderHandler()` duplicates validation logic from `createInvoiceHandler()`. Consider extracting shared validation into a domain validator. |
| LOW | The new `NotificationStrategy` interface has only one implementation. This is fine if more are planned, but if not, the direct implementation is simpler. |

### What NOT to Flag

- "This could be more generic" when there is only one use case today and no concrete plan for more.
- Architectural impurity in glue code, scripts, or one-off migration files.
- Tight coupling in test setup code — tests often need to wire things together that production code keeps separate.
- A pragmatic shortcut that the PR description explicitly calls out as intentional tech debt with a follow-up ticket.
