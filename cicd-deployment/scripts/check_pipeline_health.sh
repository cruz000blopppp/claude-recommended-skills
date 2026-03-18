#!/bin/bash
set -euo pipefail

###############################################################################
# check_pipeline_health.sh
#
# Audits a repository's CI/CD configuration across 5 categories:
#   1. CI/CD System Detection
#   2. Referenced Script Verification
#   3. Secrets Scanning
#   4. Dockerfile Best Practices
#   5. Repository Health
#
# Usage: ./check_pipeline_health.sh [path-to-repo]
#        Defaults to the current directory if no path is provided.
#
# Exit codes:
#   0 - All checks passed (no FAILs)
#   1 - One or more FAILs detected
#
# Portable across macOS and Linux.
###############################################################################

# ---------------------------------------------------------------------------
# Color support: disabled when stdout is not a terminal
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  RESET=''
fi

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# ---------------------------------------------------------------------------
# Resolve the repository path (default: current directory)
# ---------------------------------------------------------------------------
REPO_PATH="${1:-.}"
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

if [ ! -d "$REPO_PATH" ]; then
  echo "Error: '$REPO_PATH' is not a valid directory."
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Print a section header
section() {
  echo ""
  echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"
  echo ""
}

# Record a PASS result
pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "  ${GREEN}[PASS]${RESET} $1"
}

# Record a WARN result
warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  echo -e "  ${YELLOW}[WARN]${RESET} $1"
}

# Record a FAIL result
fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo -e "  ${RED}[FAIL]${RESET} $1"
}

# Portable find for CI config files — collects paths into a variable.
# Uses -maxdepth where appropriate to keep searches fast.
find_ci_files() {
  local pattern="$1"
  local dir="${2:-$REPO_PATH}"
  local depth="${3:-5}"
  # -L follows symlinks; works on both macOS and GNU find
  find -L "$dir" -maxdepth "$depth" -name "$pattern" -type f 2>/dev/null || true
}

# Collect all CI/CD config files into a single list for later scanning
collect_ci_config_files() {
  local files=""

  # GitHub Actions workflows
  if [ -d "$REPO_PATH/.github/workflows" ]; then
    files="$files $(find_ci_files '*.yml' "$REPO_PATH/.github/workflows" 3)"
    files="$files $(find_ci_files '*.yaml' "$REPO_PATH/.github/workflows" 3)"
  fi

  # CircleCI
  if [ -f "$REPO_PATH/.circleci/config.yml" ]; then
    files="$files $REPO_PATH/.circleci/config.yml"
  fi

  # Jenkins
  if [ -f "$REPO_PATH/Jenkinsfile" ]; then
    files="$files $REPO_PATH/Jenkinsfile"
  fi

  # GitLab CI
  if [ -f "$REPO_PATH/.gitlab-ci.yml" ]; then
    files="$files $REPO_PATH/.gitlab-ci.yml"
  fi

  # Bitbucket Pipelines
  if [ -f "$REPO_PATH/bitbucket-pipelines.yml" ]; then
    files="$files $REPO_PATH/bitbucket-pipelines.yml"
  fi

  # Azure DevOps
  if [ -f "$REPO_PATH/azure-pipelines.yml" ]; then
    files="$files $REPO_PATH/azure-pipelines.yml"
  fi

  echo "$files"
}

###############################################################################
# 1. CI/CD System Detection
###############################################################################
check_cicd_detection() {
  section "1. CI/CD System Detection"

  local found_any=false

  # --- CI/CD Systems ---

  # GitHub Actions
  if [ -d "$REPO_PATH/.github/workflows" ]; then
    local workflow_count
    workflow_count=$(find_ci_files '*.yml' "$REPO_PATH/.github/workflows" 3 | wc -l | tr -d ' ')
    local yaml_count
    yaml_count=$(find_ci_files '*.yaml' "$REPO_PATH/.github/workflows" 3 | wc -l | tr -d ' ')
    workflow_count=$((workflow_count + yaml_count))
    pass "GitHub Actions detected ($workflow_count workflow file(s))"
    found_any=true
  fi

  # CircleCI
  if [ -f "$REPO_PATH/.circleci/config.yml" ]; then
    pass "CircleCI detected (.circleci/config.yml)"
    found_any=true
  fi

  # Jenkins
  if [ -f "$REPO_PATH/Jenkinsfile" ]; then
    pass "Jenkins detected (Jenkinsfile)"
    found_any=true
  fi

  # GitLab CI
  if [ -f "$REPO_PATH/.gitlab-ci.yml" ]; then
    pass "GitLab CI detected (.gitlab-ci.yml)"
    found_any=true
  fi

  # Bitbucket Pipelines
  if [ -f "$REPO_PATH/bitbucket-pipelines.yml" ]; then
    pass "Bitbucket Pipelines detected (bitbucket-pipelines.yml)"
    found_any=true
  fi

  # Azure DevOps
  if [ -f "$REPO_PATH/azure-pipelines.yml" ]; then
    pass "Azure DevOps detected (azure-pipelines.yml)"
    found_any=true
  fi

  # --- Deployment Configs ---

  if [ -f "$REPO_PATH/vercel.json" ]; then
    pass "Vercel deployment config detected (vercel.json)"
    found_any=true
  fi

  if [ -f "$REPO_PATH/netlify.toml" ]; then
    pass "Netlify deployment config detected (netlify.toml)"
    found_any=true
  fi

  if [ -f "$REPO_PATH/fly.toml" ]; then
    pass "Fly.io deployment config detected (fly.toml)"
    found_any=true
  fi

  if [ -f "$REPO_PATH/render.yaml" ]; then
    pass "Render deployment config detected (render.yaml)"
    found_any=true
  fi

  if [ -f "$REPO_PATH/railway.json" ]; then
    pass "Railway deployment config detected (railway.json)"
    found_any=true
  fi

  if [ "$found_any" = false ]; then
    warn "No CI/CD system or deployment configuration detected"
  fi
}

###############################################################################
# 2. Referenced Script Verification
###############################################################################
check_referenced_scripts() {
  section "2. Referenced Script Verification"

  local ci_files
  ci_files="$(collect_ci_config_files)"

  if [ -z "$(echo "$ci_files" | tr -d ' ')" ]; then
    warn "No CI config files found; skipping script verification"
    return
  fi

  local checked_any=false

  # -----------------------------------------------------------------------
  # 2a. npm run <script> references
  # -----------------------------------------------------------------------
  if [ -f "$REPO_PATH/package.json" ]; then
    local npm_scripts
    # Extract npm run references from CI configs
    npm_scripts=$(cat $ci_files 2>/dev/null \
      | grep -oE 'npm run [a-zA-Z0-9_:.-]+' \
      | sed 's/npm run //' \
      | sort -u || true)

    for script_name in $npm_scripts; do
      checked_any=true
      # Check if the script is defined in package.json
      if grep -qE "\"$script_name\"\\s*:" "$REPO_PATH/package.json" 2>/dev/null; then
        pass "npm script '$script_name' exists in package.json"
      else
        fail "npm script '$script_name' referenced in CI but missing from package.json"
      fi
    done
  fi

  # -----------------------------------------------------------------------
  # 2b. Shell script references (./scripts/X.sh or ./X.sh patterns)
  # -----------------------------------------------------------------------
  local shell_refs
  shell_refs=$(cat $ci_files 2>/dev/null \
    | grep -oE '\./[a-zA-Z0-9_/.-]+\.sh' \
    | sort -u || true)

  for script_ref in $shell_refs; do
    checked_any=true
    local full_path="$REPO_PATH/$script_ref"

    if [ -f "$full_path" ]; then
      if [ -x "$full_path" ]; then
        pass "Script '$script_ref' exists and is executable"
      else
        warn "Script '$script_ref' exists but is NOT executable (missing +x)"
      fi
    else
      fail "Script '$script_ref' referenced in CI but file not found"
    fi
  done

  # -----------------------------------------------------------------------
  # 2c. Makefile target references
  # -----------------------------------------------------------------------
  if [ -f "$REPO_PATH/Makefile" ]; then
    local make_refs
    make_refs=$(cat $ci_files 2>/dev/null \
      | grep -oE 'make [a-zA-Z0-9_-]+' \
      | sed 's/make //' \
      | sort -u || true)

    for target in $make_refs; do
      checked_any=true
      # Check if the target is defined in the Makefile (line starting with target:)
      if grep -qE "^${target}:" "$REPO_PATH/Makefile" 2>/dev/null; then
        pass "Makefile target '$target' exists"
      else
        fail "Makefile target '$target' referenced in CI but not found in Makefile"
      fi
    done
  fi

  if [ "$checked_any" = false ]; then
    pass "No external script references found in CI configs (nothing to verify)"
  fi
}

###############################################################################
# 3. Secrets Scanning
###############################################################################
check_secrets() {
  section "3. Secrets Scanning"

  # Files to scan: CI configs, Dockerfiles, docker-compose files
  local scan_files=""
  scan_files="$(collect_ci_config_files)"
  scan_files="$scan_files $(find_ci_files 'Dockerfile*' "$REPO_PATH" 3)"
  scan_files="$scan_files $(find_ci_files 'docker-compose*.yml' "$REPO_PATH" 3)"
  scan_files="$scan_files $(find_ci_files 'docker-compose*.yaml' "$REPO_PATH" 3)"
  scan_files="$scan_files $(find_ci_files '.env*' "$REPO_PATH" 1)"

  # Remove empty entries
  scan_files="$(echo "$scan_files" | xargs)"

  if [ -z "$scan_files" ]; then
    pass "No CI/Docker files to scan for secrets"
    return
  fi

  local found_secrets=false

  # Define patterns: <label>|<regex>
  # We use extended regex (-E) for portability
  local patterns=(
    "AWS Access Key|AKIA[0-9A-Z]{16}"
    "GitHub Token (ghp_)|ghp_[A-Za-z0-9_]{36,}"
    "GitHub Token (gho_)|gho_[A-Za-z0-9_]{36,}"
    "GitHub Token (ghu_)|ghu_[A-Za-z0-9_]{36,}"
    "GitHub Token (ghs_)|ghs_[A-Za-z0-9_]{36,}"
    "Slack Token (xoxb-)|xoxb-[0-9A-Za-z-]+"
    "Slack Token (xoxp-)|xoxp-[0-9A-Za-z-]+"
    "Stripe Secret Key (sk_live_)|sk_live_[0-9a-zA-Z]{24,}"
    "Stripe Secret Key (sk_test_)|sk_test_[0-9a-zA-Z]{24,}"
    "Stripe Publishable Key (pk_live_)|pk_live_[0-9a-zA-Z]{24,}"
    "Stripe Publishable Key (pk_test_)|pk_test_[0-9a-zA-Z]{24,}"
    "Bearer Token|[Bb]earer\\s+[A-Za-z0-9_\\-\\.]{20,}"
  )

  for entry in "${patterns[@]}"; do
    local label="${entry%%|*}"
    local regex="${entry##*|}"

    for f in $scan_files; do
      [ -f "$f" ] || continue

      local matches
      matches=$(grep -nE "$regex" "$f" 2>/dev/null || true)

      if [ -n "$matches" ]; then
        found_secrets=true
        # Show file relative to repo, truncate the matched line to avoid exposing full secret
        local rel_path="${f#"$REPO_PATH"/}"
        while IFS= read -r line; do
          local line_num="${line%%:*}"
          local line_content="${line#*:}"
          # Truncate line content to first 60 chars to avoid exposing secrets
          local truncated="${line_content:0:60}"
          if [ "${#line_content}" -gt 60 ]; then
            truncated="${truncated}..."
          fi
          fail "$label found in $rel_path:$line_num — ${truncated}"
        done <<< "$matches"
      fi
    done
  done

  if [ "$found_secrets" = false ]; then
    pass "No hardcoded secrets detected in CI/Docker files"
  fi
}

###############################################################################
# 4. Dockerfile Best Practices
###############################################################################
check_dockerfile_practices() {
  section "4. Dockerfile Best Practices"

  local dockerfiles
  dockerfiles=$(find_ci_files 'Dockerfile*' "$REPO_PATH" 3)

  if [ -z "$dockerfiles" ]; then
    warn "No Dockerfiles found; skipping Dockerfile checks"
    return
  fi

  for dockerfile in $dockerfiles; do
    local rel_path="${dockerfile#"$REPO_PATH"/}"
    echo -e "  ${BOLD}Checking: $rel_path${RESET}"

    # 4a. Multi-stage builds (multiple FROM directives)
    local from_count
    from_count=$(grep -cE '^FROM ' "$dockerfile" 2>/dev/null || echo "0")
    if [ "$from_count" -gt 1 ]; then
      pass "Multi-stage build detected ($from_count stages)"
    else
      warn "Single-stage build — consider multi-stage for smaller images"
    fi

    # 4b. .dockerignore presence
    local dockerfile_dir
    dockerfile_dir=$(dirname "$dockerfile")
    if [ -f "$dockerfile_dir/.dockerignore" ] || [ -f "$REPO_PATH/.dockerignore" ]; then
      pass ".dockerignore file found"
    else
      warn "No .dockerignore file — build context may include unnecessary files"
    fi

    # 4c. Pinned base images (not using :latest)
    local latest_tags
    latest_tags=$(grep -E '^FROM .+:latest' "$dockerfile" 2>/dev/null || true)
    local untagged_images
    # Match FROM lines with no tag (no colon after image name, excluding AS aliases)
    untagged_images=$(grep -E '^FROM [a-zA-Z0-9_./-]+\s*(AS|\s*$)' "$dockerfile" 2>/dev/null \
      | grep -vE ':[a-zA-Z0-9]' || true)

    if [ -n "$latest_tags" ]; then
      fail "Base image uses :latest tag — pin to a specific version"
    elif [ -n "$untagged_images" ]; then
      warn "Base image has no explicit tag — defaults to :latest"
    else
      pass "Base images are pinned to specific versions"
    fi

    # 4d. Layer caching order: COPY package*.json before COPY . (Node.js pattern)
    # Check if there is a package.json copy before the full source copy
    local has_pkg_copy=false
    local has_source_copy=false
    local pkg_line=0
    local source_line=0
    local line_num=0

    while IFS= read -r line; do
      line_num=$((line_num + 1))
      # Check for package.json copy
      if echo "$line" | grep -qE '^COPY.*package(\*|\.json|(-lock)?\.json)'; then
        has_pkg_copy=true
        if [ "$pkg_line" -eq 0 ]; then
          pkg_line=$line_num
        fi
      fi
      # Check for broad source copy (COPY . . or COPY ./ ./)
      if echo "$line" | grep -qE '^COPY\s+\./?(\s|$)'; then
        has_source_copy=true
        if [ "$source_line" -eq 0 ]; then
          source_line=$line_num
        fi
      fi
    done < "$dockerfile"

    if [ "$has_pkg_copy" = true ] && [ "$has_source_copy" = true ]; then
      if [ "$pkg_line" -lt "$source_line" ]; then
        pass "Layer caching: package.json copied before source (line $pkg_line < $source_line)"
      else
        warn "Layer caching: package.json should be copied BEFORE source for better caching"
      fi
    elif [ "$has_source_copy" = true ] && [ "$has_pkg_copy" = false ]; then
      # Only relevant if this looks like a Node.js project
      if [ -f "$REPO_PATH/package.json" ]; then
        warn "Layer caching: consider copying package.json separately before 'COPY . .'"
      fi
    fi

    # 4e. Non-root USER directive
    if grep -qE '^USER ' "$dockerfile" 2>/dev/null; then
      # Make sure the USER is not root
      local user_val
      user_val=$(grep -E '^USER ' "$dockerfile" | tail -1 | awk '{print $2}')
      if [ "$user_val" = "root" ]; then
        warn "USER directive is set to 'root' — use a non-root user"
      else
        pass "Non-root USER directive found (USER $user_val)"
      fi
    else
      warn "No USER directive — container will run as root by default"
    fi

    echo ""
  done
}

###############################################################################
# 5. Repository Health
###############################################################################
check_repo_health() {
  section "5. Repository Health"

  # -----------------------------------------------------------------------
  # 5a. .gitignore
  # -----------------------------------------------------------------------
  if [ -f "$REPO_PATH/.gitignore" ]; then
    pass ".gitignore file exists"

    # Check for node_modules
    if grep -qE '(^|\s)node_modules(/?\s*$|/)' "$REPO_PATH/.gitignore" 2>/dev/null; then
      pass ".gitignore includes node_modules"
    elif [ -f "$REPO_PATH/package.json" ]; then
      fail ".gitignore does NOT include node_modules (Node.js project detected)"
    fi

    # Check for .env
    if grep -qE '(^|\s)\.env(\s*$|\s)' "$REPO_PATH/.gitignore" 2>/dev/null; then
      pass ".gitignore includes .env"
    else
      warn ".gitignore does NOT include .env — secrets may be committed"
    fi
  else
    fail "No .gitignore file found"
  fi

  # -----------------------------------------------------------------------
  # 5b. Lockfile presence
  # -----------------------------------------------------------------------
  local lockfile_found=false

  # Node.js lockfiles
  if [ -f "$REPO_PATH/package.json" ]; then
    if [ -f "$REPO_PATH/package-lock.json" ]; then
      pass "Lockfile found: package-lock.json (npm)"
      lockfile_found=true
    elif [ -f "$REPO_PATH/pnpm-lock.yaml" ]; then
      pass "Lockfile found: pnpm-lock.yaml (pnpm)"
      lockfile_found=true
    elif [ -f "$REPO_PATH/yarn.lock" ]; then
      pass "Lockfile found: yarn.lock (Yarn)"
      lockfile_found=true
    elif [ -f "$REPO_PATH/bun.lockb" ] || [ -f "$REPO_PATH/bun.lock" ]; then
      pass "Lockfile found: bun.lockb/bun.lock (Bun)"
      lockfile_found=true
    else
      fail "Node.js project detected but no lockfile found (npm/pnpm/yarn/bun)"
    fi
  fi

  # Python lockfiles
  if [ -f "$REPO_PATH/pyproject.toml" ] || [ -f "$REPO_PATH/setup.py" ] || [ -f "$REPO_PATH/requirements.txt" ]; then
    if [ -f "$REPO_PATH/poetry.lock" ]; then
      pass "Lockfile found: poetry.lock (Poetry)"
      lockfile_found=true
    elif [ -f "$REPO_PATH/requirements.txt" ]; then
      # requirements.txt can serve as a pinned dependency list
      if grep -qE '==' "$REPO_PATH/requirements.txt" 2>/dev/null; then
        pass "Pinned dependencies found in requirements.txt"
        lockfile_found=true
      else
        warn "requirements.txt exists but dependencies are not pinned (missing ==)"
        lockfile_found=true
      fi
    elif [ -f "$REPO_PATH/Pipfile.lock" ]; then
      pass "Lockfile found: Pipfile.lock (Pipenv)"
      lockfile_found=true
    else
      warn "Python project detected but no lockfile found (poetry.lock, Pipfile.lock, or pinned requirements.txt)"
    fi
  fi

  # Go lockfile
  if [ -f "$REPO_PATH/go.mod" ]; then
    if [ -f "$REPO_PATH/go.sum" ]; then
      pass "Lockfile found: go.sum (Go modules)"
      lockfile_found=true
    else
      warn "Go project detected but go.sum not found"
    fi
  fi

  if [ "$lockfile_found" = false ]; then
    # Only warn if we detected some kind of project but no lockfile section triggered
    if [ ! -f "$REPO_PATH/package.json" ] && [ ! -f "$REPO_PATH/go.mod" ] && \
       [ ! -f "$REPO_PATH/pyproject.toml" ] && [ ! -f "$REPO_PATH/setup.py" ] && \
       [ ! -f "$REPO_PATH/requirements.txt" ]; then
      pass "No package manager detected; lockfile check not applicable"
    fi
  fi

  # -----------------------------------------------------------------------
  # 5c. Large files (>10MB)
  # -----------------------------------------------------------------------
  local large_files
  # Use portable find + stat approach
  # macOS stat uses -f%z, GNU stat uses -c%s — detect which to use
  if stat -f%z /dev/null >/dev/null 2>&1; then
    # macOS
    large_files=$(find "$REPO_PATH" -maxdepth 5 -type f -size +10M \
      ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.next/*' \
      ! -path '*/vendor/*' ! -path '*/__pycache__/*' 2>/dev/null || true)
  else
    # Linux
    large_files=$(find "$REPO_PATH" -maxdepth 5 -type f -size +10M \
      ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.next/*' \
      ! -path '*/vendor/*' ! -path '*/__pycache__/*' 2>/dev/null || true)
  fi

  if [ -n "$large_files" ]; then
    while IFS= read -r lf; do
      local rel="${lf#"$REPO_PATH"/}"
      local size_human
      if stat -f%z /dev/null >/dev/null 2>&1; then
        # macOS
        local size_bytes
        size_bytes=$(stat -f%z "$lf" 2>/dev/null || echo "0")
        size_human="$((size_bytes / 1048576))MB"
      else
        # Linux
        size_human=$(du -h "$lf" 2>/dev/null | cut -f1)
      fi
      warn "Large file detected: $rel ($size_human)"
    done <<< "$large_files"
  else
    pass "No large files (>10MB) found outside standard ignore directories"
  fi

  # -----------------------------------------------------------------------
  # 5d. Committed .env files
  # -----------------------------------------------------------------------
  local env_files
  env_files=$(find "$REPO_PATH" -maxdepth 3 -name '.env' -o -name '.env.local' \
    -o -name '.env.production' -o -name '.env.staging' 2>/dev/null \
    | grep -v '/node_modules/' | grep -v '/.git/' || true)

  if [ -n "$env_files" ]; then
    while IFS= read -r ef; do
      local rel="${ef#"$REPO_PATH"/}"
      # If we are in a git repo, check if the file is tracked
      if [ -d "$REPO_PATH/.git" ]; then
        if git -C "$REPO_PATH" ls-files --error-unmatch "$ef" >/dev/null 2>&1; then
          fail "Committed .env file detected: $rel (may contain secrets)"
        else
          warn ".env file exists but is not tracked by git: $rel"
        fi
      else
        warn ".env file exists: $rel (not a git repo; cannot verify tracking status)"
      fi
    done <<< "$env_files"
  else
    pass "No .env files found in the repository"
  fi
}

###############################################################################
# Main execution
###############################################################################

echo -e "${BOLD}CI/CD Pipeline Health Check${RESET}"
echo -e "Repository: ${BOLD}$REPO_PATH${RESET}"
echo -e "Date:       $(date '+%Y-%m-%d %H:%M:%S')"
echo "-------------------------------------------"

check_cicd_detection
check_referenced_scripts
check_secrets
check_dockerfile_practices
check_repo_health

###############################################################################
# Summary
###############################################################################
echo ""
echo "==========================================="
echo -e "${BOLD}Summary${RESET}"
echo "==========================================="
echo -e "  ${GREEN}PASS${RESET}: $PASS_COUNT"
echo -e "  ${YELLOW}WARN${RESET}: $WARN_COUNT"
echo -e "  ${RED}FAIL${RESET}: $FAIL_COUNT"
echo "==========================================="

TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
echo "  Total checks: $TOTAL"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo -e "${RED}${BOLD}Result: FAILED${RESET} — $FAIL_COUNT issue(s) require attention."
  exit 1
else
  echo -e "${GREEN}${BOLD}Result: PASSED${RESET} — no critical issues found."
  exit 0
fi
