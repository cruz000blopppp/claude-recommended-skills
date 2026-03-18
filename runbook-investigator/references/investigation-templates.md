# Investigation Templates

Pre-built investigation checklists for the four most common failure patterns. Work through each checklist in order. Skip steps only if you have strong evidence they are not relevant.

---

## 1. Build Failure Investigation

When a build breaks and the cause is not immediately obvious.

### Checklist

1. **Read the full error message.** Not just the last line. Scroll up to the first error. Later errors are often cascading failures from the first one.

2. **Check recent dependency changes.**
   ```bash
   git diff HEAD~3..HEAD -- '*lock*' '**/package.json' '**/requirements.txt' '**/go.mod' '**/Cargo.toml'
   ```
   Look for: version bumps, new dependencies, removed dependencies, resolution conflicts.

3. **Verify runtime version.**
   ```bash
   node --version    # or python --version, go version, rustc --version
   ```
   Compare against `.nvmrc`, `.python-version`, `go.mod`, `rust-toolchain.toml`, or CI config. Mismatch between local and CI is a frequent cause.

4. **Check disk space.**
   ```bash
   df -h
   ```
   Builds fail in mysterious ways when disk is full. Look for `/tmp` and the build output directory.

5. **Clean build.**
   ```bash
   # JavaScript/TypeScript
   rm -rf node_modules .next dist build && npm install && npm run build

   # Python
   rm -rf __pycache__ .venv dist build *.egg-info && pip install -e . && python -m build

   # Go
   go clean -cache && go build ./...

   # Rust
   cargo clean && cargo build
   ```
   If clean build succeeds, the issue was stale cache or artifacts.

6. **Compare CI vs local environment.**
   - OS differences (Linux CI vs macOS local)
   - Environment variables present in CI but not local (or vice versa)
   - File path case sensitivity (macOS is case-insensitive by default, Linux is not)
   - Globally installed packages that are missing in CI

7. **Check for newly added files.**
   ```bash
   git diff --name-status HEAD~3..HEAD | grep '^A'
   ```
   Look for: case sensitivity conflicts (`Utils.ts` vs `utils.ts`), files outside expected directories, files with special characters in names.

8. **Check for circular imports.**
   - JavaScript: build tools usually report these explicitly
   - Python: `ImportError` with partially initialized modules
   - Look for recently introduced imports between modules that did not previously depend on each other

### Escalation Criteria

Escalate if:
- Clean build also fails and error is in a dependency (not your code)
- Error references infrastructure (permissions, network, registry access)
- Multiple team members reproduce the same failure with clean builds
- Error is in generated code or build tooling configuration

---

## 2. Performance Degradation Investigation

When an endpoint, operation, or system becomes measurably slower.

### Checklist

1. **Identify the slow path.**
   - Which endpoint or operation is slow? (APM traces, access logs with response times)
   - When did it start? (metrics dashboard, deployment timeline)
   - How slow? (p50, p95, p99 latency — know which percentile you are looking at)

2. **Check database queries.**
   ```sql
   -- PostgreSQL: find slow queries
   SELECT query, mean_exec_time, calls
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 20;

   -- Analyze a specific query
   EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) <your_query>;
   ```
   Look for: sequential scans on large tables, missing indexes, high row estimates vs actual.

3. **Check for N+1 query patterns.**
   - Enable query logging temporarily
   - Count queries per request. If you see dozens of similar queries with different IDs, it is N+1
   - Common in ORMs when loading related records in a loop

4. **Check cache hit rates.**
   ```bash
   # Redis
   redis-cli INFO stats | grep -E 'keyspace_hits|keyspace_misses'
   ```
   Calculate hit rate: `hits / (hits + misses)`. Below 90% warrants investigation. Check if cache was recently flushed or if keys are expiring too quickly.

5. **Check connection pool usage.**
   ```sql
   -- PostgreSQL
   SELECT count(*), state FROM pg_stat_activity GROUP BY state;
   ```
   If most connections are active/idle-in-transaction, the pool may be exhausted. Check for long-running transactions or leaked connections.

6. **Check for memory leaks.**
   - Monitor memory usage over time (not just current usage)
   - Take heap snapshots before and after load, compare retained objects
   - Look for growing arrays, caches without eviction, event listener accumulation

7. **Check recent traffic changes.**
   - Traffic spike? (more requests than usual)
   - New traffic pattern? (different endpoints, larger payloads, new user segment)
   - Bot traffic or abuse? (unusual user agents, high request rates from single IPs)

8. **Check third-party API latency.**
   - Are external calls taking longer? (APM traces for outbound HTTP)
   - Check status pages for third-party services
   - Check if timeouts are configured and appropriate

### Escalation Criteria

Escalate if:
- Degradation exceeds SLA thresholds
- Root cause is in infrastructure (DB hardware, network, cloud provider)
- Issue requires schema changes or significant architectural work
- Third-party dependency is the bottleneck and has no workaround

---

## 3. Intermittent Failure Investigation

When something fails sometimes but not always. The hardest category to debug.

### Checklist

1. **Correlate with observable dimensions.**
   - Time of day? (cron jobs, traffic patterns, batch processing windows)
   - Load level? (fails under high concurrency but not low)
   - Specific inputs? (certain user IDs, data shapes, payload sizes)
   - Geographic region? (CDN, edge caching, DNS resolution differences)
   - Specific infrastructure? (one container/pod but not others)

2. **Check for race conditions.**
   - Does the operation involve concurrent reads and writes to the same resource?
   - Are there transactions that should be serialized but are not?
   - Look for: optimistic locking failures, duplicate key violations, stale read anomalies
   ```bash
   # Search for concurrent access patterns
   grep -rn "async\|await\|Promise\|setTimeout\|setInterval\|concurrent\|parallel" --include="*.ts" --include="*.js" <path>
   ```

3. **Check resource exhaustion.**
   ```bash
   # File descriptors
   ulimit -n           # limit
   ls /proc/self/fd | wc -l  # current usage (Linux)
   lsof -p <pid> | wc -l     # current usage (macOS)

   # Connection pools
   # Check your framework's pool metrics

   # Memory
   free -m  # Linux
   vm_stat  # macOS
   ```
   Intermittent failures often correlate with approaching resource limits.

4. **Check external dependency flakiness.**
   - Review error logs for third-party API timeouts and errors
   - Check if retries are configured and whether they are causing retry storms
   - Verify DNS resolution is stable (`dig <hostname>` multiple times)

5. **Check timeout configurations.**
   - Are timeouts appropriate for the operation? (too short causes false failures)
   - Are there cascading timeouts? (caller timeout shorter than callee timeout)
   - Is there a timeout on database queries?

6. **Check for retry storms.**
   - When a request fails, do clients retry?
   - Do retries have exponential backoff and jitter?
   - Could retries be amplifying a transient issue into a sustained outage?

7. **Increase observability.**
   If the above checks yield nothing:
   - Add structured logging around the failure path
   - Add metrics for the specific operation
   - Set up alerts on the failure condition
   - Wait for the next occurrence with better instrumentation

### Escalation Criteria

Escalate if:
- Failure rate is increasing over time
- Failures correlate with data loss or corruption
- Root cause appears to be a concurrency bug in shared infrastructure
- Investigation requires production debugging tools (profilers, debuggers) that need special access

---

## 4. Environment Discrepancy Investigation ("Works on My Machine")

When behavior differs between environments (local vs CI, staging vs production, developer A vs developer B).

### Checklist

1. **Compare OS and runtime versions.**
   ```bash
   uname -a
   node --version && npm --version   # or equivalent for your stack
   docker --version                   # if using containers
   ```
   Document both environments. Even minor version differences can change behavior.

2. **Diff environment variables.**
   ```bash
   # Capture env vars (redact secrets)
   env | sort > /tmp/env-local.txt
   # Compare with CI/staging env vars (from config, not runtime)
   diff /tmp/env-local.txt /tmp/env-other.txt
   ```
   Look for: missing vars, different values, extra vars that change behavior.

3. **Check database state.**
   - Are migrations up to date in both environments?
   - Is seed/test data present in one but not the other?
   - Are there schema differences? (`pg_dump --schema-only` and diff)

4. **Check file path assumptions.**
   - Absolute paths that differ between environments
   - Case sensitivity: macOS (case-insensitive by default) vs Linux (case-sensitive)
   - Path separators: Windows (`\`) vs Unix (`/`)
   - Symlinks: do they exist in both environments?
   ```bash
   # Find case-sensitivity issues
   git ls-files | sort -f | uniq -di
   ```

5. **Check timezone and locale.**
   ```bash
   date +%Z        # timezone
   locale           # locale settings
   ```
   Date formatting, string sorting, and number formatting differ by locale.

6. **Check .env files and local config.**
   - Is `.env` in `.gitignore`? (it should be)
   - Does the working environment have a `.env` file that the broken one lacks?
   - Are there `.env.local`, `.env.development`, `.env.test` overrides?

7. **Check Docker vs native execution.**
   - If using Docker: is the Docker image the same version?
   - Volume mounts: are files being mounted correctly?
   - Network: is `localhost` resolving differently inside vs outside the container?
   - File permissions: do mounted files have the right permissions?

8. **Check implicit dependencies.**
   ```bash
   # Globally installed packages that might be masking a missing dependency
   npm list -g --depth=0       # Node.js
   pip list                     # Python (outside venv)
   which <command>              # Is a tool coming from an unexpected location?
   ```
   A globally installed package on one machine can mask a missing dependency in `package.json` or `requirements.txt`.

### Escalation Criteria

Escalate if:
- Discrepancy is in infrastructure configuration (networking, permissions, cloud provider)
- Issue requires changes to CI/CD pipeline or Docker images
- Root cause is a platform-specific bug in a dependency
- Multiple developers are affected and no workaround exists
