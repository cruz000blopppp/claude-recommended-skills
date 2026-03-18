# Idempotency Guide

Idempotency means running an operation multiple times produces the same result as running it once. This is the single most important property of any automation. Why? Because automated processes retry on failure, cron jobs overlap, users double-click, and CI pipelines re-run. If your operation is not idempotent, every retry creates a new problem.

---

## 1. File Operations

### Problem

Creating a file that already exists, or appending to a file on every run, produces different results each time.

### Patterns

**Check existence before create:**

```bash
# NOT idempotent: fails if file exists, or overwrites silently
echo "config" > /etc/app/config.yaml

# Idempotent: only creates if missing
if [ ! -f /etc/app/config.yaml ]; then
  echo "config" > /etc/app/config.yaml
  echo "[INFO] Created config.yaml"
else
  echo "[INFO] config.yaml already exists, skipping"
fi
```

**Content hash comparison before write:**

```typescript
import { createHash } from 'crypto'
import { readFile, writeFile } from 'fs/promises'

async function writeIfChanged(filePath: string, newContent: string): Promise<boolean> {
  try {
    const existing = await readFile(filePath, 'utf-8')
    const existingHash = createHash('sha256').update(existing).digest('hex')
    const newHash = createHash('sha256').update(newContent).digest('hex')

    if (existingHash === newHash) {
      console.log(`[INFO] ${filePath} unchanged, skipping`)
      return false
    }
  } catch {
    // File doesn't exist yet, proceed with write
  }

  await writeIfChanged_atomic(filePath, newContent)
  console.log(`[INFO] ${filePath} updated`)
  return true
}
```

**Atomic write with rename:**

```typescript
import { writeFile, rename } from 'fs/promises'
import { join, dirname } from 'path'

async function atomicWrite(filePath: string, content: string): Promise<void> {
  const tempPath = join(dirname(filePath), `.${Date.now()}.tmp`)

  try {
    await writeFile(tempPath, content, 'utf-8')
    await rename(tempPath, filePath)
  } catch (error) {
    // Clean up temp file on failure
    try { await unlink(tempPath) } catch { /* already gone */ }
    throw error
  }
}
```

Why atomic write matters: if the process crashes mid-write, you get a corrupt file. With rename, the file is either fully old or fully new — never partially written.

---

## 2. Database Operations

### Problem

Inserting a record that already exists either fails (unique constraint violation) or creates duplicates (no constraint). Both are wrong for automation.

### Patterns

**Upsert with ON CONFLICT (PostgreSQL):**

```sql
-- Idempotent: inserts if new, updates if exists
INSERT INTO users (id, email, name, updated_at)
VALUES ($1, $2, $3, NOW())
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  name = EXCLUDED.name,
  updated_at = NOW();
```

**INSERT WHERE NOT EXISTS:**

```sql
-- Idempotent: only inserts if the record is truly missing
INSERT INTO settings (key, value)
SELECT 'theme', 'dark'
WHERE NOT EXISTS (
  SELECT 1 FROM settings WHERE key = 'theme'
);
```

**Migration version tracking:**

```typescript
interface Migration {
  readonly version: string
  readonly name: string
  readonly up: () => Promise<void>
  readonly down: () => Promise<void>
}

async function runMigrations(db: Database, migrations: readonly Migration[]): Promise<void> {
  // Create tracking table if it doesn't exist (idempotent)
  await db.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version TEXT PRIMARY KEY,
      applied_at TIMESTAMP DEFAULT NOW()
    )
  `)

  const applied = await db.query('SELECT version FROM schema_migrations')
  const appliedSet = new Set(applied.rows.map(r => r.version))

  for (const migration of migrations) {
    if (appliedSet.has(migration.version)) {
      console.log(`[INFO] Migration ${migration.version} already applied, skipping`)
      continue
    }

    console.log(`[INFO] Applying migration ${migration.version}: ${migration.name}`)
    await migration.up()
    await db.query(
      'INSERT INTO schema_migrations (version) VALUES ($1)',
      [migration.version]
    )
  }
}
```

---

## 3. API Operations

### Problem

POST requests create new resources every time. Retrying a failed POST that actually succeeded on the server creates duplicates.

### Patterns

**PUT vs POST:**

```typescript
// NOT idempotent: creates a new resource each time
await fetch('/api/users', { method: 'POST', body: JSON.stringify(user) })

// Idempotent: creates or replaces the resource at this ID
await fetch(`/api/users/${user.id}`, { method: 'PUT', body: JSON.stringify(user) })
```

**Idempotency keys:**

```typescript
import { randomUUID } from 'crypto'

async function createPayment(amount: number, idempotencyKey?: string): Promise<Payment> {
  const key = idempotencyKey ?? randomUUID()

  const response = await fetch('/api/payments', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': key,
    },
    body: JSON.stringify({ amount }),
  })

  if (response.status === 409) {
    // Already processed with this key — fetch the existing result
    console.log(`[INFO] Payment already processed for key ${key}`)
    return response.json()
  }

  return response.json()
}
```

**Request deduplication on the server side:**

```typescript
async function handleRequest(
  db: Database,
  idempotencyKey: string,
  handler: () => Promise<unknown>
): Promise<{ status: number; body: unknown }> {
  // Check if this request was already processed
  const existing = await db.query(
    'SELECT response_status, response_body FROM idempotency_cache WHERE key = $1',
    [idempotencyKey]
  )

  if (existing.rows.length > 0) {
    const cached = existing.rows[0]
    return { status: cached.response_status, body: JSON.parse(cached.response_body) }
  }

  // Process the request
  const result = await handler()

  // Cache the response
  await db.query(
    'INSERT INTO idempotency_cache (key, response_status, response_body, created_at) VALUES ($1, $2, $3, NOW())',
    [idempotencyKey, 200, JSON.stringify(result)]
  )

  return { status: 200, body: result }
}
```

---

## 4. Process Operations

### Problem

Automation scripts that run concurrently or restart after failure can duplicate work or corrupt state.

### Patterns

**Lockfiles to prevent concurrent execution:**

```bash
LOCKFILE="/tmp/my-automation.lock"

cleanup() {
  rm -f "$LOCKFILE"
}

if [ -f "$LOCKFILE" ]; then
  pid=$(cat "$LOCKFILE")
  if kill -0 "$pid" 2>/dev/null; then
    echo "[WARN] Another instance is running (PID: $pid). Exiting."
    exit 0
  else
    echo "[INFO] Stale lockfile found (PID: $pid no longer running). Removing."
    rm -f "$LOCKFILE"
  fi
fi

echo $$ > "$LOCKFILE"
trap cleanup EXIT
```

**Checkpoint files for resumable operations:**

```typescript
interface Checkpoint {
  readonly lastProcessedId: string
  readonly processedCount: number
  readonly startedAt: string
}

async function processWithCheckpoint(
  items: readonly Item[],
  checkpointPath: string,
  processor: (item: Item) => Promise<void>
): Promise<void> {
  let checkpoint: Checkpoint | null = null

  try {
    const raw = await readFile(checkpointPath, 'utf-8')
    checkpoint = JSON.parse(raw)
    console.log(`[INFO] Resuming from checkpoint: ${checkpoint.lastProcessedId}`)
  } catch {
    console.log('[INFO] No checkpoint found, starting from beginning')
  }

  let startIndex = 0
  if (checkpoint) {
    startIndex = items.findIndex(i => i.id === checkpoint!.lastProcessedId) + 1
  }

  for (let i = startIndex; i < items.length; i++) {
    await processor(items[i])

    // Write checkpoint after each successful operation
    const newCheckpoint: Checkpoint = {
      lastProcessedId: items[i].id,
      processedCount: (checkpoint?.processedCount ?? 0) + 1,
      startedAt: checkpoint?.startedAt ?? new Date().toISOString(),
    }
    await writeFile(checkpointPath, JSON.stringify(newCheckpoint, null, 2))
  }

  // Clean up checkpoint after successful completion
  try { await unlink(checkpointPath) } catch { /* already gone */ }
}
```

---

## 5. Distributed Operations

### Problem

In distributed systems, messages can be delivered more than once, network partitions cause retries, and multiple nodes may attempt the same work.

### Patterns

**At-least-once delivery with deduplication:**

```typescript
interface ProcessedMessage {
  readonly messageId: string
  readonly processedAt: Date
}

async function handleMessage(
  db: Database,
  messageId: string,
  handler: () => Promise<void>
): Promise<void> {
  // Check if already processed
  const existing = await db.query(
    'SELECT 1 FROM processed_messages WHERE message_id = $1',
    [messageId]
  )

  if (existing.rows.length > 0) {
    console.log(`[INFO] Message ${messageId} already processed, skipping`)
    return
  }

  // Process within a transaction
  await db.query('BEGIN')
  try {
    await handler()
    await db.query(
      'INSERT INTO processed_messages (message_id, processed_at) VALUES ($1, NOW())',
      [messageId]
    )
    await db.query('COMMIT')
  } catch (error) {
    await db.query('ROLLBACK')
    throw error
  }
}
```

**Distributed locks with expiry:**

```typescript
async function withDistributedLock<T>(
  redis: Redis,
  lockKey: string,
  ttlSeconds: number,
  operation: () => Promise<T>
): Promise<T | null> {
  const lockValue = randomUUID()

  // Acquire lock (SET NX EX is atomic)
  const acquired = await redis.set(lockKey, lockValue, 'EX', ttlSeconds, 'NX')

  if (!acquired) {
    console.log(`[WARN] Could not acquire lock: ${lockKey}`)
    return null
  }

  try {
    return await operation()
  } finally {
    // Release lock only if we still own it (compare-and-delete)
    const script = `
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    `
    await redis.eval(script, 1, lockKey, lockValue)
  }
}
```

Key insight: always set a TTL on distributed locks. A crashed process that holds a lock forever blocks all other instances permanently.

---

## 6. Testing Idempotency

The simplest and most reliable test for idempotency: **run the automation twice and diff the results.**

### The Two-Run Test

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Run 1 ==="
./my-automation.sh > /tmp/run1.log 2>&1
cp -r ./output /tmp/output-run1

echo "=== Run 2 ==="
./my-automation.sh > /tmp/run2.log 2>&1
cp -r ./output /tmp/output-run2

echo "=== Diff ==="
if diff -r /tmp/output-run1 /tmp/output-run2 > /dev/null 2>&1; then
  echo "PASS: Outputs are identical. Operation is idempotent."
else
  echo "FAIL: Outputs differ. Operation is NOT idempotent."
  diff -r /tmp/output-run1 /tmp/output-run2
  exit 1
fi
```

### Database Idempotency Test

```typescript
async function testIdempotency(seedFunction: () => Promise<void>): Promise<void> {
  // Run 1
  await seedFunction()
  const countAfterRun1 = await db.query('SELECT COUNT(*) as count FROM target_table')

  // Run 2
  await seedFunction()
  const countAfterRun2 = await db.query('SELECT COUNT(*) as count FROM target_table')

  if (countAfterRun1.rows[0].count !== countAfterRun2.rows[0].count) {
    throw new Error(
      `Not idempotent: row count changed from ${countAfterRun1.rows[0].count} to ${countAfterRun2.rows[0].count}`
    )
  }

  console.log(`PASS: Row count stable at ${countAfterRun1.rows[0].count} after two runs`)
}
```

### What to Check Beyond Row Counts

- **Timestamps**: Did `updated_at` change on the second run? If so, decide whether that's acceptable.
- **Side effects**: Were emails sent twice? Were webhooks fired twice? Were files written twice?
- **Logs**: Does the second run log "created" or "skipped/updated"? "Created" on the second run means it's not idempotent.
- **External state**: Did the automation modify external systems (APIs, caches, queues) on both runs?

### Automated Idempotency in CI

Add a step to your CI pipeline that runs every automation script twice and asserts identical outcomes. This catches idempotency regressions before they reach production, where a retry loop will expose them at the worst possible moment.
