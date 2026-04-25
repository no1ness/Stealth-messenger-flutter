---
name: frontend-pro
description: Implements and refactors frontend features with minimal diffs, clear acceptance criteria, and safe verification. Use when building UI components, fixing visual/interaction bugs, improving accessibility, handling state, integrating APIs, or reviewing frontend code quality.
license: MIT
metadata:
  author: custom
  version: "1.0.0"
  category: frontend
---

# Frontend Pro

Practical frontend execution rules for daily product work.

## Scope

Use for:
- UI components and page layout
- Styling and responsive behavior
- Interactive logic and state handling
- API integration on the client side
- Accessibility and basic performance improvements

## Workflow

1. Clarify goal and constraints.
2. Define acceptance criteria.
3. Implement the smallest valid change.
4. Verify behavior with concrete checks.
5. Report exactly what changed and why.

## Core Rules

### 1) Think Before Coding

- If the request is ambiguous, ask concise clarifying questions first.
- State key assumptions before implementation.
- If there are multiple approaches, propose the simplest one first.

### 2) Simplicity First

- Implement only requested scope.
- Avoid speculative abstractions and premature architecture changes.
- Reuse existing components, utilities, and patterns before adding new ones.

### 3) Surgical Changes

- Keep diff narrow: only necessary files and lines.
- Avoid unrelated refactors, formatting sweeps, and renames.
- Keep existing naming/style conventions unless user asked to change them.

### 4) Goal-Driven Execution

- Convert request into verifiable acceptance criteria.
- Prefer deterministic validation:
  - lint/typecheck for touched files
  - targeted tests when available
  - manual reproduction steps for UI behavior
- Do not mark done without verification results.

## Frontend Quality Checklist

- Accessibility: labels, keyboard flow, focus visibility, semantic structure.
- Responsive behavior: key breakpoints remain usable.
- Loading and error states: user feedback is explicit.
- API handling: empty/error/slow responses handled gracefully.
- Regressions: unchanged screens still work as before.

## Output Format

When finishing a frontend task, include:
- What changed (files and behavior)
- Why this approach was chosen
- How it was verified (commands and/or manual steps)
- Any remaining risks or follow-up items
---
name: frontend-pro
description: Implements and refactors frontend features with minimal diffs, clear acceptance criteria, and safe verification. Use when building UI components, fixing visual/interaction bugs, improving accessibility, handling state, integrating APIs, or reviewing frontend code quality.
license: MIT
metadata:
  author: custom
  version: "1.0.0"
  category: frontend
---

# Frontend Pro

Practical frontend execution rules for daily product work.

## Scope

Use for:
- UI components and page layout
- Styling and responsive behavior
- Interactive logic and state handling
- API integration on the client side
- Accessibility and basic performance improvements

## Workflow

1. Clarify goal and constraints.
2. Define acceptance criteria.
3. Implement the smallest valid change.
4. Verify behavior with concrete checks.
5. Report exactly what changed and why.

## Core Rules

### 1) Think Before Coding

- If the request is ambiguous, ask concise clarifying questions first.
- State key assumptions before implementation.
- If there are multiple approaches, propose the simplest one first.

### 2) Simplicity First

- Implement only requested scope.
- Avoid speculative abstractions and premature architecture changes.
- Reuse existing components, utilities, and patterns before adding new ones.

### 3) Surgical Changes

- Keep diff narrow: only necessary files and lines.
- Avoid unrelated refactors, formatting sweeps, and renames.
- Keep existing naming/style conventions unless user asked to change them.

### 4) Goal-Driven Execution

- Convert request into verifiable acceptance criteria.
- Prefer deterministic validation:
  - lint/typecheck for touched files
  - targeted tests when available
  - manual reproduction steps for UI behavior
- Do not mark done without verification results.

## Frontend Quality Checklist

- Accessibility: labels, keyboard flow, focus visibility, semantic structure.
- Responsive behavior: key breakpoints remain usable.
- Loading and error states: user feedback is explicit.
- API handling: empty/error/slow responses handled gracefully.
- Regressions: unchanged screens still work as before.

## Output Format

When finishing a frontend task, include:
- What changed (files and behavior)
- Why this approach was chosen
- How it was verified (commands and/or manual steps)
- Any remaining risks or follow-up items
