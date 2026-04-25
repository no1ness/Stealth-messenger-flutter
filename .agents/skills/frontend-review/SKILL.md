---
name: frontend-review
description: Reviews frontend changes for correctness, regressions, accessibility, UX risks, and maintainability. Use when reviewing pull requests, staged diffs, or local changes in UI logic, styling, component architecture, and client-side data flow.
license: MIT
metadata:
  author: custom
  version: "1.0.0"
  category: frontend
---

# Frontend Review

Review frontend changes with issue-first output and severity ordering.

## Review Priorities

Order findings by severity:
1. Critical bugs/regressions
2. Security/privacy risks
3. Accessibility failures
4. Data/async correctness issues
5. Performance and maintainability issues

## What To Check

### Correctness
- Logic matches requirements.
- Edge states handled: empty, loading, error, partial data.
- No broken user flow after changes.

### Regressions
- Existing behavior remains intact.
- Shared components did not break other screens.
- Backward compatibility for expected API shape.

### Accessibility
- Keyboard navigation works.
- Interactive elements are reachable and labeled.
- Focus handling is predictable in dialogs/forms.
- Color contrast or visibility is not degraded by styling changes.

### UX and State
- Clear feedback on loading and failure.
- No flicker or stale data after updates.
- Debounce/throttle or duplicate requests are handled correctly.

### Performance
- No unnecessary re-renders in hot paths.
- Heavy computations memoized only when justified.
- Asset or bundle impact is reasonable for scope.

## Review Output Format

- Findings first, ordered by severity.
- Each finding includes:
  - what is wrong
  - why it matters
  - concrete fix suggestion
- Then include:
  - open questions/assumptions
  - short change summary
  - test gaps or residual risks

## Review Rules

- Prefer concrete, reproducible issues over stylistic opinions.
- Do not request broad refactors unless they are required to fix a real risk.
- If no issues found, explicitly say so and list remaining test gaps.
---
name: frontend-review
description: Reviews frontend changes for correctness, regressions, accessibility, UX risks, and maintainability. Use when reviewing pull requests, staged diffs, or local changes in UI logic, styling, component architecture, and client-side data flow.
license: MIT
metadata:
  author: custom
  version: "1.0.0"
  category: frontend
---

# Frontend Review

Review frontend changes with issue-first output and severity ordering.

## Review Priorities

Order findings by severity:
1. Critical bugs/regressions
2. Security/privacy risks
3. Accessibility failures
4. Data/async correctness issues
5. Performance and maintainability issues

## What To Check

### Correctness
- Logic matches requirements.
- Edge states handled: empty, loading, error, partial data.
- No broken user flow after changes.

### Regressions
- Existing behavior remains intact.
- Shared components did not break other screens.
- Backward compatibility for expected API shape.

### Accessibility
- Keyboard navigation works.
- Interactive elements are reachable and labeled.
- Focus handling is predictable in dialogs/forms.
- Color contrast or visibility is not degraded by styling changes.

### UX and State
- Clear feedback on loading and failure.
- No flicker or stale data after updates.
- Debounce/throttle or duplicate requests are handled correctly.

### Performance
- No unnecessary re-renders in hot paths.
- Heavy computations memoized only when justified.
- Asset or bundle impact is reasonable for scope.

## Review Output Format

- Findings first, ordered by severity.
- Each finding includes:
  - what is wrong
  - why it matters
  - concrete fix suggestion
- Then include:
  - open questions/assumptions
  - short change summary
  - test gaps or residual risks

## Review Rules

- Prefer concrete, reproducible issues over stylistic opinions.
- Do not request broad refactors unless they are required to fix a real risk.
- If no issues found, explicitly say so and list remaining test gaps.
