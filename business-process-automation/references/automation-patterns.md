# Automation Patterns

Detailed implementation patterns for six common development workflow automations. Each pattern covers the problem, solution approach, implementation sketch, verification steps, and common failures.

---

## 1. Release Notes Generation

### Problem

Manually writing release notes is tedious, inconsistent, and often forgotten. Developers write code, merge PRs, and tag releases — but the "what changed" summary for users gets lost between the git log and the release page.

### Solution Approach

Parse the git log between two tags (or a tag and HEAD), group commits by conventional commit type, format as structured markdown, and output to stdout or a file.

### Implementation Sketch

```bash
#!/usr/bin/env bash
set -euo pipefail

PREVIOUS_TAG="${1:-$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")}"
CURRENT_TAG="${2:-HEAD}"

if [ -z "$PREVIOUS_TAG" ]; then
  echo "ERROR: No previous tag found. Provide one explicitly." >&2
  exit 1
fi

echo "# Release Notes: ${CURRENT_TAG}"
echo ""
echo "Changes since ${PREVIOUS_TAG}:"
echo ""

# Group by conventional commit type
for type_label in "feat:Features" "fix:Bug Fixes" "perf:Performance" "refactor:Refactoring" "docs:Documentation"; do
  prefix="${type_label%%:*}"
  heading="${type_label##*:}"

  commits=$(git log "${PREVIOUS_TAG}..${CURRENT_TAG}" --pretty=format:"- %s (%h)" \
    --grep="^${prefix}" 2>/dev/null || true)

  if [ -n "$commits" ]; then
    echo "## ${heading}"
    echo ""
    echo "$commits"
    echo ""
  fi
done

# Catch commits that don't follow conventional format
other=$(git log "${PREVIOUS_TAG}..${CURRENT_TAG}" --pretty=format:"- %s (%h)" \
  --grep="^feat\|^fix\|^perf\|^refactor\|^docs\|^chore\|^test\|^ci" --invert-grep 2>/dev/null || true)

if [ -n "$other" ]; then
  echo "## Other Changes"
  echo ""
  echo "$other"
  echo ""
fi
```

### Handling Squash Merges

When the repo uses squash merges, individual commit messages are lost. Instead, parse PR titles from merge commits:

```bash
git log "${PREVIOUS_TAG}..${CURRENT_TAG}" --merges --pretty=format:"%s" \
  | sed 's/Merge pull request #\([0-9]*\) from .*/PR #\1/' \
  | while read -r line; do
      echo "- ${line}"
    done
```

For GitHub repos, use the API for richer data:

```bash
gh api "repos/{owner}/{repo}/releases/generate-notes" \
  -f tag_name="${CURRENT_TAG}" \
  -f previous_tag_name="${PREVIOUS_TAG}" \
  --jq '.body'
```

### Verification Steps

- Compare commit count in release notes against `git rev-list --count PREV..CURRENT`
- Check that no commits are duplicated across categories
- Verify links to issues/PRs resolve correctly
- Run against a known release and diff against hand-written notes

### Common Failures

- **Missing tags**: Script breaks if tags don't exist. Always validate inputs.
- **Non-conventional commits**: Commits without prefixes end up uncategorized. Include an "Other" section.
- **Monorepo scope**: In monorepos, filter commits by path to avoid including unrelated changes.
- **Encoding issues**: Commit messages with special characters break markdown. Sanitize output.

---

## 2. Changelog Management

### Problem

Changelogs drift from reality. Developers forget to update them, formatting is inconsistent, and "Unreleased" sections grow unbounded between releases.

### Solution Approach

Use [Keep a Changelog](https://keepachangelog.com/) format. Auto-categorize entries from conventional commits. Manage the "Unreleased" section automatically and cut it into a versioned section on release.

### Implementation Sketch

```typescript
interface ChangelogEntry {
  readonly type: 'Added' | 'Changed' | 'Deprecated' | 'Removed' | 'Fixed' | 'Security'
  readonly description: string
  readonly pr?: number
}

const COMMIT_TYPE_MAP: Record<string, ChangelogEntry['type']> = {
  feat: 'Added',
  fix: 'Fixed',
  refactor: 'Changed',
  perf: 'Changed',
  deprecate: 'Deprecated',
  security: 'Security',
}

function parseCommitToEntry(message: string): ChangelogEntry | null {
  const match = message.match(/^(\w+)(?:\(.*?\))?:\s*(.+)/)
  if (!match) return null

  const [, commitType, description] = match
  const type = COMMIT_TYPE_MAP[commitType]
  if (!type) return null

  const prMatch = description.match(/#(\d+)/)
  return {
    type,
    description: description.replace(/#\d+/, '').trim(),
    pr: prMatch ? parseInt(prMatch[1], 10) : undefined,
  }
}

function cutRelease(changelog: string, version: string, date: string): string {
  const unreleased = '## [Unreleased]'
  const newSection = [
    unreleased,
    '',
    `## [${version}] - ${date}`,
  ].join('\n')

  return changelog.replace(unreleased, newSection)
}
```

### Version Bumping Logic

Determine the version bump from commit types:

- Any `feat` commit → minor bump
- Any commit with `BREAKING CHANGE` in body or `!` after type → major bump
- Only `fix`, `perf`, `refactor` → patch bump

### Verification Steps

- Parse the generated changelog and verify markdown is valid
- Check that version numbers are monotonically increasing
- Verify date format is ISO 8601 (YYYY-MM-DD)
- Confirm every entry in "Unreleased" maps to an actual commit

### Common Failures

- **Merge conflicts**: CHANGELOG.md is a frequent source of merge conflicts. Consider generating it entirely from git history to eliminate manual edits.
- **Duplicate entries**: Same commit picked up in multiple releases. Track processed commits by hash.
- **Missing categories**: Empty categories should be omitted, not shown with no entries.

---

## 3. Dependency Updates

### Problem

Dependencies go stale, security vulnerabilities accumulate, and bulk-updating everything at once creates untraceable breakage.

### Solution Approach

Batch updates by risk level (patch → minor → major). Run tests per batch. Create PRs with clear impact summaries so reviewers know what changed and why.

### Implementation Sketch

```bash
#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-true}"

echo "=== Dependency Update Report ==="
echo ""

# Check for outdated packages
outdated=$(npm outdated --json 2>/dev/null || echo "{}")

# Group by update type
for update_type in patch minor major; do
  packages=$(echo "$outdated" | jq -r \
    --arg type "$update_type" \
    'to_entries[] | select(.value.type == $type) | "\(.key): \(.value.current) → \(.value.wanted)"')

  if [ -n "$packages" ]; then
    echo "## ${update_type^} Updates"
    echo "$packages"
    echo ""

    if [ "$DRY_RUN" = "false" ]; then
      echo "$outdated" | jq -r \
        --arg type "$update_type" \
        'to_entries[] | select(.value.type == $type) | .key' \
        | xargs -I{} npm install {}@latest

      echo "Running tests for ${update_type} batch..."
      if ! npm test; then
        echo "ERROR: Tests failed after ${update_type} updates. Rolling back."
        git checkout package.json package-lock.json
        npm install
        exit 1
      fi
    fi
  fi
done
```

### PR Creation with Impact Summary

After each batch passes tests, create a PR:

```bash
gh pr create \
  --title "chore(deps): update ${update_type} dependencies" \
  --body "$(cat <<EOF
## Dependency Updates (${update_type})

${packages}

### Test Results
- Unit tests: PASS
- Integration tests: PASS
- Build: PASS

### Risk Assessment
- Update type: ${update_type}
- Packages affected: $(echo "$packages" | wc -l)
EOF
)"
```

### Verification Steps

- All tests pass after each batch
- Lockfile is consistent (`npm ci` succeeds on a clean install)
- No peer dependency warnings introduced
- Build output size hasn't changed dramatically

### Common Failures

- **Peer dependency conflicts**: One update breaks another package's peer requirement. Process one package at a time for major updates.
- **Lockfile drift**: Updating without committing the lockfile leads to inconsistent installs. Always commit both `package.json` and lockfile together.
- **Transitive breakage**: A patch update in a direct dependency pulls a breaking change in a transitive dependency. Pin transitive dependencies when needed.

---

## 4. Environment Variable Sync

### Problem

Environment variables drift between `.env.example`, local `.env`, staging, and production. New variables get added to code but not to deployment configs. Missing variables cause runtime crashes in production.

### Solution Approach

Treat `.env.example` as the source of truth for required variables. Detect drift, report missing/extra variables, and sync non-secret values automatically.

### Implementation Sketch

```typescript
interface EnvSyncResult {
  readonly missing: readonly string[]
  readonly extra: readonly string[]
  readonly matching: readonly string[]
}

function parseEnvFile(content: string): ReadonlyMap<string, string> {
  const entries = content
    .split('\n')
    .filter(line => line.trim() && !line.startsWith('#'))
    .map(line => {
      const eqIndex = line.indexOf('=')
      if (eqIndex === -1) return null
      return [line.slice(0, eqIndex).trim(), line.slice(eqIndex + 1).trim()] as const
    })
    .filter((entry): entry is readonly [string, string] => entry !== null)

  return new Map(entries)
}

function detectDrift(example: ReadonlyMap<string, string>, actual: ReadonlyMap<string, string>): EnvSyncResult {
  const exampleKeys = new Set(example.keys())
  const actualKeys = new Set(actual.keys())

  return {
    missing: [...exampleKeys].filter(k => !actualKeys.has(k)),
    extra: [...actualKeys].filter(k => !exampleKeys.has(k)),
    matching: [...exampleKeys].filter(k => actualKeys.has(k)),
  }
}
```

### Secret vs Non-Secret Handling

Mark variables as secrets in `.env.example` with a comment convention:

```bash
# Non-secret: safe to sync automatically
APP_PORT=3000
LOG_LEVEL=info

# SECRET: must be set manually per environment
DATABASE_URL=postgresql://user:password@localhost/db
API_KEY=your-api-key-here
```

Automation syncs non-secret values automatically and reports secret variables that need manual attention.

### Verification Steps

- After sync, application starts without missing-variable errors
- No secrets are committed to version control
- All environments have the same set of variable names (values may differ)

### Common Failures

- **Quoted values**: Some tools handle `KEY="value"` differently from `KEY=value`. Normalize during parsing.
- **Multiline values**: Values with newlines break naive parsers. Support escaped newlines or quoted blocks.
- **Variable expansion**: `${OTHER_VAR}` references may not resolve in all environments. Avoid cross-references in `.env` files.

---

## 5. Database Seed Data

### Problem

Development and test databases need consistent seed data. Manually inserting records is fragile. Running seed scripts twice creates duplicates or constraint violations.

### Solution Approach

Write idempotent seed scripts that use upsert operations, respect referential integrity through ordered insertion, and support environment-specific data sets.

### Implementation Sketch

```typescript
interface SeedConfig {
  readonly environment: 'development' | 'test' | 'staging'
  readonly cleanFirst: boolean
  readonly dryRun: boolean
}

interface SeedResult {
  readonly table: string
  readonly inserted: number
  readonly updated: number
  readonly skipped: number
}

async function seedTable(
  db: Database,
  table: string,
  records: readonly Record<string, unknown>[],
  config: SeedConfig
): Promise<SeedResult> {
  let inserted = 0
  let updated = 0
  let skipped = 0

  for (const record of records) {
    if (config.dryRun) {
      console.log(`[DRY RUN] Would upsert into ${table}:`, record)
      skipped++
      continue
    }

    const result = await db.query(
      `INSERT INTO ${table} (${Object.keys(record).join(', ')})
       VALUES (${Object.keys(record).map((_, i) => `$${i + 1}`).join(', ')})
       ON CONFLICT (id) DO UPDATE SET
       ${Object.keys(record).filter(k => k !== 'id').map(k => `${k} = EXCLUDED.${k}`).join(', ')}
       RETURNING (xmax = 0) AS is_insert`,
      Object.values(record)
    )

    if (result.rows[0].is_insert) {
      inserted++
    } else {
      updated++
    }
  }

  return { table, inserted, updated, skipped }
}
```

### Insertion Order for Referential Integrity

Define table dependencies and seed in topological order:

```typescript
const SEED_ORDER = [
  'organizations',  // no dependencies
  'users',          // depends on organizations
  'projects',       // depends on organizations
  'tasks',          // depends on projects, users
  'comments',       // depends on tasks, users
] as const
```

### Cleanup Procedures

For test environments, clean in reverse dependency order:

```typescript
async function cleanSeedData(db: Database): Promise<void> {
  const reverseOrder = [...SEED_ORDER].reverse()
  for (const table of reverseOrder) {
    await db.query(`DELETE FROM ${table} WHERE seeded = true`)
  }
}
```

Mark seeded data with a `seeded` flag or a known ID range to distinguish from user-created data.

### Verification Steps

- Run seed script twice — second run should report 0 inserts, N updates (or skips)
- Query each table and verify expected row counts
- Test foreign key relationships are intact
- Run application and verify seeded data appears correctly

### Common Failures

- **ID conflicts**: Auto-incrementing IDs collide with hardcoded seed IDs. Use UUIDs or a reserved ID range.
- **Order of operations**: Inserting a child record before the parent violates foreign keys. Always follow dependency order.
- **Stale seeds**: Seed data drifts from the current schema. Run seeds in CI to catch breakage early.

---

## 6. Notification Routing

### Problem

Teams need to know when things happen (PR merged, deploy succeeded, tests failed) but notifications are either missing, duplicated, or sent to the wrong channel.

### Solution Approach

Define event-to-notification mappings declaratively. Route to the appropriate channel based on event type and severity. Deduplicate and rate-limit to prevent notification fatigue.

### Implementation Sketch

```typescript
interface NotificationRule {
  readonly event: string
  readonly channel: 'slack' | 'email' | 'webhook'
  readonly target: string
  readonly severity: 'info' | 'warning' | 'critical'
  readonly template: string
  readonly dedupeKey?: string
  readonly cooldownMinutes?: number
}

const RULES: readonly NotificationRule[] = [
  {
    event: 'deploy.succeeded',
    channel: 'slack',
    target: '#deployments',
    severity: 'info',
    template: 'Deployed {{version}} to {{environment}}',
    cooldownMinutes: 5,
  },
  {
    event: 'deploy.failed',
    channel: 'slack',
    target: '#incidents',
    severity: 'critical',
    template: 'FAILED: Deploy {{version}} to {{environment}} — {{error}}',
    dedupeKey: 'deploy-fail-{{environment}}',
    cooldownMinutes: 15,
  },
  {
    event: 'test.failed',
    channel: 'slack',
    target: '#ci',
    severity: 'warning',
    template: 'Tests failed on {{branch}}: {{failCount}} failures',
    dedupeKey: 'test-fail-{{branch}}',
    cooldownMinutes: 30,
  },
]
```

### Deduplication and Rate Limiting

Track sent notifications to prevent duplicates:

```typescript
interface SentNotification {
  readonly dedupeKey: string
  readonly sentAt: Date
}

function shouldSend(
  rule: NotificationRule,
  context: Record<string, string>,
  recentlySent: readonly SentNotification[]
): boolean {
  if (!rule.dedupeKey) return true

  const resolvedKey = rule.dedupeKey.replace(
    /\{\{(\w+)\}\}/g,
    (_, key) => context[key] ?? ''
  )

  const existing = recentlySent.find(n => n.dedupeKey === resolvedKey)
  if (!existing) return true

  const cooldownMs = (rule.cooldownMinutes ?? 0) * 60 * 1000
  const elapsed = Date.now() - existing.sentAt.getTime()
  return elapsed > cooldownMs
}
```

### Verification Steps

- Trigger each event type and verify the correct channel receives the notification
- Trigger the same event twice within the cooldown window — second should be suppressed
- Verify critical notifications are never suppressed by rate limiting
- Test with malformed event data — should log a warning, not crash

### Common Failures

- **Webhook timeouts**: External services (Slack, email) can be slow or down. Use async delivery with retries, not synchronous calls.
- **Template injection**: User-controlled data in templates can break formatting. Escape special characters (especially for Slack markdown).
- **Alert fatigue**: Too many notifications train people to ignore them. Start with fewer, higher-signal notifications and add more only when requested.
- **Missing context**: "Tests failed" without a link to the failing build is useless. Always include actionable links.
