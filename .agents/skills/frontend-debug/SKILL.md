---
name: frontend-debug
description: Debugs frontend issues using reproducible steps and evidence-first investigation. Use when UI behavior is broken, JavaScript errors appear, state updates fail, async data flow is inconsistent, or regressions are suspected.
license: MIT
metadata:
  author: custom
  version: "1.0.0"
  category: frontend
---

# Frontend Debug

Systematic frontend debugging workflow focused on fast root-cause isolation.

## Debug Rules

- Reproduce first, then fix.
- Do not patch blindly without evidence.
- Change one hypothesis at a time.
- Keep fixes minimal and regression-safe.

## Workflow

1. Reproduce
- Capture exact steps, expected result, and actual result.
- Identify scope: browser(s), route, role, device width, data preconditions.

2. Collect evidence
- Console errors and warnings
- Network request failures (status, payload shape, timing)
- State/props snapshots at failure point
- DOM state (missing element, wrong class, disabled state)

3. Isolate root cause
- Confirm whether issue is in:
  - rendering condition
  - state mutation/update order
  - async race/timing
  - API contract mismatch
  - CSS/layout conflict

4. Apply minimal fix
- Change only lines needed to remove root cause.
- Avoid refactoring unrelated code.

5. Verify
- Re-run reproduction steps.
- Validate nearby scenarios to prevent regressions.
- Report proof: what failed before and what passes now.

## Investigation Checklist

- Does the bug reproduce consistently?
- Is there a clear failing condition?
- Is data shape what UI expects?
- Is state derived from stale source?
- Are effects/subscriptions cleaned up correctly?
- Is CSS specificity/overflow/z-index causing hidden UI?

## Output Format

- Symptom summary
- Root cause
- Minimal fix description
- Verification results
- Residual risks (if any)
---
name: frontend-debug
description: Debugs frontend issues using reproducible steps and evidence-first investigation. Use when UI behavior is broken, JavaScript errors appear, state updates fail, async data flow is inconsistent, or regressions are suspected.
license: MIT
metadata:
  author: custom
  version: "1.0.0"
  category: frontend
---

# Frontend Debug

Systematic frontend debugging workflow focused on fast root-cause isolation.

## Debug Rules

- Reproduce first, then fix.
- Do not patch blindly without evidence.
- Change one hypothesis at a time.
- Keep fixes minimal and regression-safe.

## Workflow

1. Reproduce
- Capture exact steps, expected result, and actual result.
- Identify scope: browser(s), route, role, device width, data preconditions.

2. Collect evidence
- Console errors and warnings
- Network request failures (status, payload shape, timing)
- State/props snapshots at failure point
- DOM state (missing element, wrong class, disabled state)

3. Isolate root cause
- Confirm whether issue is in:
  - rendering condition
  - state mutation/update order
  - async race/timing
  - API contract mismatch
  - CSS/layout conflict

4. Apply minimal fix
- Change only lines needed to remove root cause.
- Avoid refactoring unrelated code.

5. Verify
- Re-run reproduction steps.
- Validate nearby scenarios to prevent regressions.
- Report proof: what failed before and what passes now.

## Investigation Checklist

- Does the bug reproduce consistently?
- Is there a clear failing condition?
- Is data shape what UI expects?
- Is state derived from stale source?
- Are effects/subscriptions cleaned up correctly?
- Is CSS specificity/overflow/z-index causing hidden UI?

## Output Format

- Symptom summary
- Root cause
- Minimal fix description
- Verification results
- Residual risks (if any)
