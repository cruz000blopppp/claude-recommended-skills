# GitHub Actions Patterns

Reusable patterns for production-grade GitHub Actions workflows. Each pattern includes a YAML example, usage guidance, and common pitfalls.

---

## 1. Dependency Caching

Cache dependencies to dramatically reduce build times. Always key caches on the lockfile hash so they invalidate when dependencies change.

### npm

```yaml
- name: Cache npm dependencies
  uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      npm-${{ runner.os }}-

- name: Install dependencies
  run: npm ci
```

### pnpm

```yaml
- name: Install pnpm
  uses: pnpm/action-setup@v4
  with:
    version: 9

- name: Get pnpm store directory
  id: pnpm-cache
  shell: bash
  run: echo "STORE_PATH=$(pnpm store path --silent)" >> "$GITHUB_OUTPUT"

- name: Cache pnpm dependencies
  uses: actions/cache@v4
  with:
    path: ${{ steps.pnpm-cache.outputs.STORE_PATH }}
    key: pnpm-${{ runner.os }}-${{ hashFiles('**/pnpm-lock.yaml') }}
    restore-keys: |
      pnpm-${{ runner.os }}-

- name: Install dependencies
  run: pnpm install --frozen-lockfile
```

### yarn (v3+)

```yaml
- name: Cache yarn dependencies
  uses: actions/cache@v4
  with:
    path: .yarn/cache
    key: yarn-${{ runner.os }}-${{ hashFiles('**/yarn.lock') }}
    restore-keys: |
      yarn-${{ runner.os }}-

- name: Install dependencies
  run: yarn install --immutable
```

### pip

```yaml
- name: Cache pip dependencies
  uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: pip-${{ runner.os }}-${{ hashFiles('**/requirements*.txt') }}
    restore-keys: |
      pip-${{ runner.os }}-

- name: Install dependencies
  run: pip install -r requirements.txt
```

### Go Modules

```yaml
- name: Cache Go modules
  uses: actions/cache@v4
  with:
    path: |
      ~/go/pkg/mod
      ~/.cache/go-build
    key: go-${{ runner.os }}-${{ hashFiles('**/go.sum') }}
    restore-keys: |
      go-${{ runner.os }}-
```

**When to use**: Every workflow that installs dependencies. The cache hit rate on lockfile-keyed caches is very high for most projects.

**Pitfalls**:
- Cache size limits exist (10 GB per repo on GitHub). Prune old caches periodically.
- `restore-keys` fallback can restore stale caches. This is usually fine for dependency caches but can cause subtle issues with build caches.
- Always use `npm ci` (not `npm install`) to ensure lockfile-driven installs.

---

## 2. Matrix Builds

Run the same job across multiple OS/version combinations.

### Basic Matrix

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        node-version: [18, 20, 22]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
      - run: npm ci
      - run: npm test
```

### Matrix with Exclusions and Inclusions

```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    node-version: [18, 20, 22]
    exclude:
      # Skip Node 18 on Windows -- not a supported target
      - os: windows-latest
        node-version: 18
    include:
      # Add a specific combination with extra env
      - os: ubuntu-latest
        node-version: 22
        experimental: true
```

**When to use**: Libraries that must support multiple runtimes or platforms. Application code typically only needs one OS and one version.

**Pitfalls**:
- Matrix explosion: 3 x 3 = 9 jobs. Each consumes minutes. Constrain to what you actually ship.
- `fail-fast: true` (default) cancels all matrix jobs when one fails. Set to `false` to see all failures at once, which is usually more useful for debugging.
- Windows runners use `\` path separators and have case-insensitive filesystems -- test scripts may need adjustment.

---

## 3. Conditional Execution

Run jobs only when relevant files change, saving CI minutes.

### Path Filters with dorny/paths-filter

```yaml
jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      frontend: ${{ steps.filter.outputs.frontend }}
      backend: ${{ steps.filter.outputs.backend }}
      infra: ${{ steps.filter.outputs.infra }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            frontend:
              - 'src/frontend/**'
              - 'package.json'
              - 'pnpm-lock.yaml'
            backend:
              - 'src/backend/**'
              - 'requirements.txt'
            infra:
              - 'terraform/**'
              - 'Dockerfile'

  test-frontend:
    needs: changes
    if: ${{ needs.changes.outputs.frontend == 'true' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm test

  test-backend:
    needs: changes
    if: ${{ needs.changes.outputs.backend == 'true' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt
      - run: pytest
```

### Branch Filters

```yaml
on:
  push:
    branches: [main, release/*]
  pull_request:
    branches: [main]
```

### Skip Patterns

```yaml
on:
  push:
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '.vscode/**'
      - 'LICENSE'
```

### Cancel In-Progress Runs

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

**When to use**: Monorepos, projects with distinct frontend/backend, or repos where docs changes should not trigger builds.

**Pitfalls**:
- `paths-ignore` and `paths` cannot be combined in the same trigger. Use one or the other.
- Path filters on `pull_request` compare against the base branch. On `push`, they compare against the previous commit.
- `cancel-in-progress` can interrupt deployments. Exclude deployment workflows or use `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`.

---

## 4. Reusable Workflows

Share workflow logic across repositories or within a monorepo.

### Reusable Workflow Definition (called workflow)

```yaml
# .github/workflows/reusable-test.yml
name: Reusable Test Workflow

on:
  workflow_call:
    inputs:
      node-version:
        required: false
        type: string
        default: '20'
      working-directory:
        required: false
        type: string
        default: '.'
    secrets:
      NPM_TOKEN:
        required: false

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
      - run: npm ci
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      - run: npm test
```

### Calling the Reusable Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  test:
    uses: ./.github/workflows/reusable-test.yml
    with:
      node-version: '22'
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### Composite Action

```yaml
# .github/actions/setup-project/action.yml
name: Setup Project
description: Install dependencies and build

inputs:
  node-version:
    description: Node.js version
    required: false
    default: '20'

runs:
  using: composite
  steps:
    - uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
    - name: Cache dependencies
      uses: actions/cache@v4
      with:
        path: ~/.npm
        key: npm-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
    - name: Install dependencies
      run: npm ci
      shell: bash
    - name: Build
      run: npm run build
      shell: bash
```

**When to use**: When multiple repos share the same CI patterns. Composite actions are better for reusable steps within a workflow; `workflow_call` is better for reusable entire workflows.

**Pitfalls**:
- Reusable workflows can only be nested one level deep (a reusable workflow cannot call another reusable workflow).
- Secrets must be explicitly passed -- they are not inherited by default. Use `secrets: inherit` to pass all secrets (but be explicit when possible).
- Composite actions require `shell: bash` on every `run` step.

---

## 5. Artifact Management

Pass build outputs between jobs or preserve them for debugging.

### Upload and Download Artifacts

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm run build
      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: build-output
          path: dist/
          retention-days: 7

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Download build artifacts
        uses: actions/download-artifact@v4
        with:
          name: build-output
          path: dist/
      - name: Deploy
        run: ./scripts/deploy.sh dist/
```

### Test Coverage Reports

```yaml
- name: Upload coverage report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: coverage-report-${{ matrix.node-version }}
    path: coverage/
    retention-days: 14
```

**When to use**: When downstream jobs need build output, or when you want to preserve test reports and coverage data for inspection.

**Pitfalls**:
- Artifacts v4 uses immutable uploads -- you cannot overwrite an artifact with the same name in the same run. Use unique names (append matrix values or job IDs).
- Large artifacts slow down upload/download. Compress before uploading if possible.
- Retention defaults vary. Set explicit `retention-days` to control storage costs.
- Artifacts are scoped to a workflow run -- they cannot be shared across separate workflow runs without using external storage.

---

## 6. Environment Protection

Control deployments with approval gates and restrictions.

### Environment with Required Reviewers

```yaml
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://myapp.com
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to production
        run: ./scripts/deploy.sh production
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

Configure in GitHub Settings > Environments:
- **Required reviewers**: Specify team members who must approve
- **Wait timer**: Add a delay (e.g., 5 minutes) before deployment starts
- **Deployment branches**: Restrict to `main` or `release/*`

### Staging Then Production

```yaml
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment:
      name: staging
      url: https://staging.myapp.com
    steps:
      - run: ./scripts/deploy.sh staging

  smoke-test-staging:
    needs: deploy-staging
    runs-on: ubuntu-latest
    steps:
      - run: ./scripts/smoke-test.sh https://staging.myapp.com

  deploy-production:
    needs: smoke-test-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://myapp.com
    steps:
      - run: ./scripts/deploy.sh production
```

**When to use**: Any deployment to a shared or production environment. Even small teams benefit from the audit trail that environments provide.

**Pitfalls**:
- Environment secrets override repository secrets with the same name. This is a feature, but it can be confusing.
- Required reviewers block the workflow run, not just the job. Other jobs in the same workflow can continue if they do not depend on the protected job.
- Wait timers start after approval, not after the job is queued.

---

## 7. Secrets Management

Secure handling of credentials in workflows.

### Environment-Scoped Secrets

```yaml
jobs:
  deploy:
    environment: production
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: ./scripts/deploy.sh
        env:
          # This secret only exists in the "production" environment
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### OIDC for Cloud Providers (Recommended)

Eliminate long-lived credentials entirely by using GitHub's OIDC provider.

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: us-east-1

      - name: Deploy to S3
        run: aws s3 sync dist/ s3://my-bucket/
```

### Masking Custom Secrets

```yaml
- name: Generate temporary token
  id: token
  run: |
    TOKEN=$(./scripts/generate-token.sh)
    echo "::add-mask::$TOKEN"
    echo "TOKEN=$TOKEN" >> "$GITHUB_OUTPUT"

- name: Use token
  run: ./scripts/deploy.sh
  env:
    DEPLOY_TOKEN: ${{ steps.token.outputs.TOKEN }}
```

**When to use**: Always use environment secrets for deployment credentials. Use OIDC when deploying to AWS, GCP, or Azure -- it eliminates the risk of leaked long-lived credentials entirely.

**Pitfalls**:
- Secrets are not available in pull requests from forks. Use `pull_request_target` cautiously -- it runs in the context of the base branch with access to secrets, which is a security risk if the workflow checks out PR code.
- Secret values are masked in logs but can still be exfiltrated by a malicious step (e.g., base64-encoding and printing). Only grant secret access to trusted actions and scripts.
- `GITHUB_TOKEN` permissions should follow least privilege. Set `permissions` at the job level, not the workflow level.
- OIDC trust policies must be scoped tightly (to specific repos, branches, and environments) to prevent unauthorized access from other repositories.
