# Verification Checklist Templates

Use these checklists as starting points. Copy the relevant template, fill in the specifics for your feature, and check off items as you verify them. Add evidence or notes for each item.

---

## 1. API Endpoint Verification

**Endpoint:** `[METHOD] /api/[path]`
**Description:** [what this endpoint does]

| # | Check | Pass/Fail | Evidence / Notes |
|---|-------|-----------|------------------|
| 1 | **Request contract** — Sending a valid request returns the expected response shape (all required fields present, correct types) | [ ] | |
| 2 | **Success status code** — Returns the correct HTTP status (200 for GET, 201 for POST create, 204 for DELETE, etc.) | [ ] | |
| 3 | **Error codes** — Invalid input returns 400, missing auth returns 401, forbidden returns 403, missing resource returns 404 | [ ] | |
| 4 | **Authentication** — Unauthenticated requests are rejected. Expired or malformed tokens return 401. | [ ] | |
| 5 | **Authorization** — Users can only access resources they own or have permission for. Cross-tenant access is blocked. | [ ] | |
| 6 | **Rate limiting** — Exceeding the rate limit returns 429 with a Retry-After header | [ ] | |
| 7 | **Pagination** — Large result sets are paginated. Page size, offset/cursor, and total count are correct. | [ ] | |
| 8 | **Idempotency** — Repeating the same POST/PUT request does not create duplicate resources (if applicable) | [ ] | |
| 9 | **Input validation** — Malformed, oversized, or missing required fields return clear 400 errors with descriptive messages | [ ] | |
| 10 | **Response body content** — The actual data in the response is correct, not just the status code. Verify field values match expected state. | [ ] | |

---

## 2. UI Component Verification

**Component:** [component name]
**Location:** [page/route where it appears]

| # | Check | Pass/Fail | Evidence / Notes |
|---|-------|-----------|------------------|
| 1 | **Renders correctly** — The component appears on the page with expected content, layout, and styling | [ ] | |
| 2 | **Interactive elements** — Buttons, links, inputs, dropdowns, toggles respond to user interaction correctly | [ ] | |
| 3 | **Form behavior** — Form fields accept input, validation messages appear for invalid input, submission triggers the correct action | [ ] | |
| 4 | **Loading state** — A loading indicator appears while async data is being fetched. No flash of empty content. | [ ] | |
| 5 | **Error state** — Network errors, server errors, and empty states display appropriate messages. No unhandled exceptions. | [ ] | |
| 6 | **Responsive layout** — Component renders correctly at mobile (375px), tablet (768px), and desktop (1280px) viewports | [ ] | |
| 7 | **Accessibility** — Keyboard navigation works. Screen reader labels are present. Color contrast meets WCAG AA. Focus management is correct. | [ ] | |
| 8 | **Data binding** — Displayed data reflects the current backend state. Changes made through the UI are persisted. | [ ] | |

---

## 3. Data Pipeline Verification

**Pipeline:** [pipeline name]
**Input source:** [where data comes from]
**Output destination:** [where data goes]

| # | Check | Pass/Fail | Evidence / Notes |
|---|-------|-----------|------------------|
| 1 | **Input validation** — Malformed, missing, or out-of-range input records are rejected with clear error logging | [ ] | |
| 2 | **Transformation correctness** — A known input produces the exact expected output. Compare field-by-field. | [ ] | |
| 3 | **Output format** — The output conforms to the expected schema (column names, types, encoding, delimiter) | [ ] | |
| 4 | **Error handling** — Individual record failures do not crash the pipeline. Failed records are logged and skipped or dead-lettered. | [ ] | |
| 5 | **Idempotency** — Running the pipeline twice on the same input does not produce duplicate records in the output | [ ] | |
| 6 | **Performance** — The pipeline processes the expected volume within the time budget. No unbounded memory growth. | [ ] | |
| 7 | **Empty input** — An empty input source completes gracefully without errors. Output is empty, not corrupted. | [ ] | |
| 8 | **Backpressure / throttling** — The pipeline respects rate limits of downstream systems. No overloading external APIs. | [ ] | |
| 9 | **Data integrity** — Row counts match between input and output (minus expected filtered/errored records). Checksums or hashes match. | [ ] | |

---

## 4. Background Job Verification

**Job:** [job name]
**Trigger:** [what starts this job: cron, event, queue message]

| # | Check | Pass/Fail | Evidence / Notes |
|---|-------|-----------|------------------|
| 1 | **Triggers correctly** — The job starts when its trigger condition is met (schedule fires, event is published, message arrives) | [ ] | |
| 2 | **Completes successfully** — The job runs to completion and produces the expected side effects (records updated, files written, notifications sent) | [ ] | |
| 3 | **Failure handling** — When the job encounters an error, it logs the error, marks itself as failed, and does not leave state in a half-finished condition | [ ] | |
| 4 | **Retry behavior** — Failed jobs are retried the configured number of times with appropriate backoff. Permanent failures stop retrying. | [ ] | |
| 5 | **No duplicate work** — If the same job is triggered twice (at-least-once delivery), it does not produce duplicate side effects | [ ] | |
| 6 | **Timeout handling** — Jobs that exceed their time budget are killed gracefully. Resources are released. | [ ] | |
| 7 | **Logging and observability** — The job logs its start, progress, completion, and any errors. Job status is visible in the monitoring system. | [ ] | |
| 8 | **Concurrency** — Multiple instances of the job can run simultaneously without data corruption (or the job correctly acquires a lock to prevent concurrent execution) | [ ] | |

---

## 5. Authentication Flow Verification

**Auth method:** [session-based, JWT, OAuth, etc.]
**Provider:** [custom, Auth0, Firebase, Clerk, etc.]

| # | Check | Pass/Fail | Evidence / Notes |
|---|-------|-----------|------------------|
| 1 | **Login** — Valid credentials produce a session/token. The user is redirected to the authenticated area. | [ ] | |
| 2 | **Invalid login** — Wrong password returns a generic error (not "password incorrect"). Account is not locked on first attempt. | [ ] | |
| 3 | **Logout** — Session/token is invalidated. Subsequent requests with the old token are rejected (401). | [ ] | |
| 4 | **Token refresh** — Expired access tokens are refreshed automatically using the refresh token. The user is not logged out unexpectedly. | [ ] | |
| 5 | **Permission checks** — Authenticated users can only access routes and resources matching their role/permissions. Elevation is blocked. | [ ] | |
| 6 | **Session management** — Sessions expire after the configured timeout. Active sessions can be listed and revoked. | [ ] | |
| 7 | **Expired token** — An expired token returns 401, not 500. The client handles this by redirecting to login or refreshing. | [ ] | |
| 8 | **Revoked token** — A manually revoked token is immediately rejected, not accepted until natural expiry. | [ ] | |
| 9 | **Cross-device** — Logging in on a new device does not invalidate sessions on other devices (unless configured to do so). | [ ] | |
| 10 | **Password reset / account recovery** — The reset flow works: request, email received, link valid, new password accepted, old password rejected. | [ ] | |

---

## How to Use These Checklists

1. **Copy** the relevant template into your verification report.
2. **Remove** items that do not apply to your specific change.
3. **Add** items specific to your feature that the template does not cover.
4. **Fill in** the evidence column with concrete proof: response bodies, screenshots, log excerpts, database query results.
5. **Mark** each item as pass or fail. Do not leave items blank — mark them as SKIP with a reason if not applicable.
6. **Summarize** results at the bottom using the verification report format from SKILL.md.
