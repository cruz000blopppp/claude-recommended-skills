# Claude Recommended Skills

[![Stars](https://img.shields.io/github/stars/VersoXBT/claude-recommended-skills?style=flat)](https://github.com/VersoXBT/claude-recommended-skills/stargazers)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Skills-blueviolet?logo=anthropic&logoColor=white)](https://docs.anthropic.com/en/docs/claude-code)

The 9 skill categories recommended by the Anthropic team for Claude Code — production-ready, battle-tested, and ready to install.

> Based on ["Lessons from Building Claude Code: How We Use Skills"](https://x.com/trq212/status/2033949937936085378) by [Thariq](https://x.com/trq212), Anthropic engineer.

---

## Why These Skills?

The Anthropic team identified **9 high-impact skill categories** that represent the most valuable ways teams use Claude Code. Each skill in this repo implements one category with:

- **Pushy, trigger-focused descriptions** — activates when you need it, not when you don't
- **"Gotchas" sections** — real failure modes from production use, not theoretical warnings
- **Progressive disclosure** — SKILL.md stays lean, heavy content lives in `references/`
- **Theory of mind** — explains *why* before *how*, so Claude adapts to your context
- **Executable scripts** — portable helpers Claude can compose with directly

---

## Skills

| # | Skill | What It Does |
|---|-------|-------------|
| 1 | [`library-api-reference`](library-api-reference/) | Document, look up, and troubleshoot internal libraries and SDKs |
| 2 | [`product-verification`](product-verification/) | Verify code changes produce correct product behavior, not just "it compiles" |
| 3 | [`code-scaffolding`](code-scaffolding/) | Generate boilerplate that matches your existing codebase conventions |
| 4 | [`code-quality-review`](code-quality-review/) | Structured 4-pass code review with severity classification |
| 5 | [`cicd-deployment`](cicd-deployment/) | Manage CI/CD pipelines, deployments, and release workflows |
| 6 | [`data-fetch-analysis`](data-fetch-analysis/) | Safely query databases, monitoring systems, and APIs — analyze and report |
| 7 | [`business-process-automation`](business-process-automation/) | Automate repetitive workflows with reliability, observability, and rollback |
| 8 | [`runbook-investigator`](runbook-investigator/) | Structured incident investigation using the OODA loop — evidence before action |
| 9 | [`infra-operations`](infra-operations/) | Routine infrastructure maintenance: health checks, certs, deps, capacity |

---

## Installation

### One-liner (recommended)

```bash
npx skills add https://github.com/VersoXBT/claude-recommended-skills
```

### Install individual skills

```bash
# Copy a single skill to your Claude Code skills directory
git clone https://github.com/VersoXBT/claude-recommended-skills.git /tmp/claude-skills
cp -r /tmp/claude-skills/code-quality-review ~/.claude/skills/
```

### Install all skills manually

```bash
git clone https://github.com/VersoXBT/claude-recommended-skills.git /tmp/claude-skills
cp -r /tmp/claude-skills/*/ ~/.claude/skills/
rm -rf /tmp/claude-skills
```

### Project-level installation

To install skills for a specific project only:

```bash
# From your project root
mkdir -p .claude/skills
cp -r /path/to/claude-recommended-skills/runbook-investigator .claude/skills/
```

---

## What's Inside Each Skill

```
skill-name/
├── SKILL.md              # Main skill definition (frontmatter + instructions)
└── references/           # Deep-dive docs loaded on demand
    ├── patterns.md       # Reusable patterns and templates
    └── guide.md          # Detailed reference material
```

Some skills also include `scripts/` with portable Bash helpers that Claude can execute directly.

### File Inventory

- **9** SKILL.md files — one per skill
- **20** reference documents — templates, rubrics, checklists, decision trees, runbooks
- **2** executable scripts — CI/CD pipeline health checker, infrastructure health checker

---

## Skill Highlights

### `runbook-investigator` — Stop guessing, start investigating

Uses the OODA loop (Observe-Orient-Decide-Act) to enforce evidence-based debugging. Includes a triage decision tree, investigation log format, and pre-built templates for build failures, performance issues, intermittent bugs, and "works on my machine" scenarios.

### `code-scaffolding` — Convention-first, not convention-last

Analyzes 3-5 existing files of the same type in your codebase before generating anything. Detects naming conventions, export styles, test patterns, and directory structure — then generates code that looks like your team wrote it.

### `cicd-deployment` — Pipelines that don't surprise you

Covers the full lifecycle: detection of existing CI systems, pipeline architecture (5 stages), build optimization (caching, parallelism, conditionals), deployment strategies (blue-green, canary, feature flags), and structured rollback procedures. Includes a `check_pipeline_health.sh` script that audits your pipeline config for common issues.

### `data-fetch-analysis` — Safe queries, clear answers

Safety-first: read-only by default, always LIMIT, never expose credentials. Includes query patterns for time-series analysis, anomaly detection, funnel analysis, and top-N queries with PostgreSQL examples.

---

## Origin

These skills implement the 9 categories from [Thariq's article](https://x.com/trq212/status/2033949937936085378) on how the Anthropic team uses Claude Code skills internally. The article identifies these as the highest-impact skill patterns across real engineering workflows.

Key principles from the article applied here:

1. **Gotchas sections** — Every skill documents real failure modes
2. **Progressive disclosure** — File system organizes context by relevance
3. **Scripts and helpers** — Executable code Claude can compose with
4. **Flexibility over specificity** — Adapt to any stack, not locked to one framework
5. **Config-driven setup** — User context in config files, not hardcoded

---

## Contributing

PRs welcome. When adding or improving skills:

- Keep SKILL.md under 400 lines — offload to `references/`
- Include a Gotchas section with real failure modes
- Make descriptions trigger-focused (list specific phrases that should activate the skill)
- Explain "why" before "how"
- Test with `claude skill check` after changes

---

## License

MIT
