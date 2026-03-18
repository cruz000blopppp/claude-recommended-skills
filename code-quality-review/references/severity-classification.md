# Severity Classification

A systematic framework for classifying code review findings. Consistency in severity keeps reviews productive and actionable.

---

## Decision Tree

Use this flowchart to classify each finding. Start at the top and follow the first "yes" branch.

```
Finding identified
│
├─ Does it break functionality for users in production?
│  YES → Does it affect data integrity or security?
│  │      YES → CRITICAL
│  │      NO  → Is it easily triggered by normal usage?
│  │             YES → CRITICAL
│  │             NO  → HIGH
│  │
│  NO ↓
│
├─ Is it a security vulnerability?
│  YES → Can it be exploited without authentication?
│  │      YES → CRITICAL
│  │      NO  → Is sensitive data exposed?
│  │             YES → CRITICAL
│  │             NO  → HIGH
│  │
│  NO ↓
│
├─ Does it violate an established team convention?
│  YES → Is the convention documented or widely followed?
│  │      YES → Will it compound if left unfixed?
│  │      │      YES → HIGH
│  │      │      NO  → MEDIUM
│  │      NO  → MEDIUM
│  │
│  NO ↓
│
├─ Is the impact measurable (performance, maintenance cost, readability)?
│  YES → Can you articulate the specific scenario where it matters?
│  │      YES → Is the impact significant in realistic conditions?
│  │      │      YES → MEDIUM
│  │      │      NO  → LOW
│  │      NO  → LOW
│  │
│  NO ↓
│
├─ Is it a stylistic or personal preference issue?
│  YES → NIT
│  │
│  NO → Ask yourself: would you reject a PR over this?
│        YES → Re-evaluate from the top — you may have missed a branch.
│        NO  → LOW
```

---

## Finding Type to Severity Mapping

| Finding Type | Typical Severity | Example |
|---|---|---|
| SQL injection | CRITICAL | User input concatenated into query string |
| XSS vulnerability | CRITICAL | Unsanitized HTML rendered from user input |
| Authentication bypass | CRITICAL | Missing auth middleware on protected endpoint |
| Data loss risk | CRITICAL | DELETE operation without confirmation or soft-delete |
| Unhandled null dereference on critical path | CRITICAL | Payment amount accessed on possibly-null order |
| Secret in source code | CRITICAL | API key hardcoded in committed file |
| Silent error swallowing | HIGH | Empty catch block on network request |
| Missing input validation at boundary | HIGH | API endpoint accepts unvalidated body |
| Convention violation (documented) | HIGH | Mutating objects when codebase uses immutable patterns |
| Missing error context | HIGH | `catch (e) { throw e }` without adding context |
| Resource leak | HIGH | Database connection opened but not closed in error path |
| Misleading name | MEDIUM | Function called `validate()` that also saves to database |
| Missing edge case handling | MEDIUM | No handling for empty array input |
| Hardcoded magic number | MEDIUM | `if (retries > 3)` without named constant |
| Duplicated logic | MEDIUM | Same 15-line block in two handlers |
| Overly broad type | MEDIUM | Using `any` where a specific type is feasible |
| Unnecessary complexity | LOW | Ternary chain that would be clearer as if/else |
| Suboptimal but correct approach | LOW | Using `forEach` + push instead of `map` |
| Missing JSDoc on public API | LOW | Exported function without parameter documentation |
| Verbose code | LOW | 10 lines that could be 4 with no clarity loss |
| Import ordering | NIT | Third-party and local imports not separated |
| Trailing whitespace | NIT | Extra blank lines at end of file |
| Bracket style | NIT | Same-line vs next-line opening brace |
| Variable name preference | NIT | `items` vs `itemList` when both are clear |

---

## Context-Based Severity Adjustments

Severity is not absolute. Adjust based on context.

### When to Upgrade Severity

| Condition | Adjustment |
|---|---|
| The code is in a **payment, auth, or data migration** path | Upgrade one level |
| The pattern will be **copied by other developers** (e.g., a new shared utility) | Upgrade one level |
| The issue has **caused incidents before** in this codebase | Upgrade one level |
| The code is in a **high-traffic hot path** | Upgrade one level (for performance findings) |
| The finding is in **new code** (not legacy) | Holds at current level — no excuse for new tech debt |

### When to Downgrade Severity

| Condition | Adjustment |
|---|---|
| The code is a **hotfix** for a production incident | Downgrade one level (follow up with a ticket) |
| The finding is in **test code** | Downgrade one level |
| The finding is in **prototype/spike** code | Downgrade one level |
| The issue exists in **surrounding unchanged code** | Downgrade to NIT or omit entirely |
| A **follow-up ticket** already exists for this issue | Downgrade to LOW or omit |
| The code is **scheduled for removal** in a known timeline | Downgrade one level |

---

## The Rule of Three

**When you are unsure between two severity levels, pick the lower one.**

This rule exists because:

1. **Over-severity erodes trust.** If every finding is HIGH or CRITICAL, the author stops taking reviews seriously. Severity inflation is the fastest way to make reviews feel adversarial.

2. **Under-severity is correctable.** If you mark something MEDIUM and the team agrees it is HIGH, the discussion is constructive. If you mark something CRITICAL and the team disagrees, the discussion is defensive.

3. **The author has context you lack.** What looks like a mistake from outside may be a deliberate trade-off. Giving the author room to explain (at a lower severity) produces better conversations than demanding justification (at a higher severity).

### Applying the Rule

- Unsure between CRITICAL and HIGH? → **HIGH**. If it is truly critical, the author will recognize it and fix it anyway.
- Unsure between HIGH and MEDIUM? → **MEDIUM**. Frame it as "I think this should be fixed, but I may be missing context."
- Unsure between MEDIUM and LOW? → **LOW**. Suggest the improvement without blocking the PR.
- Unsure between LOW and NIT? → **NIT**. Mark it as optional and let the author decide.

---

## Common Severity Mistakes

| Mistake | Why It Is Wrong | Correct Approach |
|---|---|---|
| Marking all convention violations as CRITICAL | Convention violations rarely break production | HIGH if documented and compounding, MEDIUM otherwise |
| Marking performance concerns as HIGH without data | Intuition about performance is unreliable | LOW unless you can describe the realistic scenario and estimate impact |
| Marking personal preferences as MEDIUM | Personal preference is not a team agreement | NIT, always |
| Marking pre-existing issues in unchanged code as HIGH | The current PR did not introduce the problem | NIT or omit; file a separate tech debt ticket |
| Marking everything in a large PR as LOW to avoid conflict | Under-reviewing is as harmful as over-reviewing | Apply the decision tree honestly; large PRs often contain genuine HIGH findings |
| Flagging a workaround without acknowledging the constraint | Sometimes the "right" solution is blocked by external factors | Ask about the constraint before assigning severity |

---

## Severity and PR Decisions

Use severity to drive the review recommendation:

| Findings Present | Recommendation |
|---|---|
| Any CRITICAL | **REQUEST CHANGES** — must fix before merge |
| Any HIGH, no CRITICAL | **REQUEST CHANGES** — should fix before merge |
| MEDIUM only | **APPROVE** with comments — author decides whether to address now or later |
| LOW and NIT only | **APPROVE** — findings are suggestions, not blockers |
| No findings | **APPROVE** — explicitly state the code looks good |
