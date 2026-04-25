# AGENTS.md

> Universal baseline rules for AI agents. Reuse this file across different projects.

## Purpose

This file defines default execution behavior:

- keep changes minimal and request-scoped
- avoid hidden assumptions
- prefer simple, maintainable solutions
- verify outcomes before claiming completion

## Core Rules

### 1) Think Before Coding

- State assumptions explicitly.
- If requirements are ambiguous, ask concise clarifying questions first.
- If multiple valid interpretations exist, present options briefly.
- If a simpler approach exists, recommend it.

### 2) Simplicity First

- Implement only what was requested.
- Avoid speculative abstractions and premature architecture.
- Reuse existing patterns before introducing new layers.
- Prefer the smallest clear change that solves the task.

### 3) Surgical Changes

- Change only files and lines required for the task.
- Do not perform unrelated refactors or formatting sweeps.
- Keep existing style and conventions unless asked to change them.
- Remove only artifacts introduced by your own changes.

### 4) Goal-Driven Execution

- Define concrete success criteria before implementation.
- Validate with reproducible checks (build, lint, tests, or explicit manual steps).
- For multi-step work, verify each step before moving on.

## Safety & Quality

### MUST

- Keep diffs narrow, reviewable, and reversible.
- Preserve existing behavior unless behavior change is requested.
- Run the most relevant validation for touched areas.
- Report blockers early with concrete evidence.
- Be explicit about what changed and how it was verified.

### NEVER

- Never invent requirements not requested by the user.
- Never modify unrelated modules "while you are here."
- Never claim verification you did not run.
- Never run destructive commands unless explicitly approved.
- Never expose secrets or commit sensitive credentials.

## Recommended Skill Layout

Use reusable skills under:

- `.agents/skills/karpathy-guidelines/SKILL.md`
- `.agents/skills/frontend-pro/SKILL.md`
- `.agents/skills/frontend-debug/SKILL.md`
- `.agents/skills/frontend-review/SKILL.md`
- add stack-specific skills only when relevant to the target project

## Final Checklist

- [ ] Assumptions were explicit or clarified.
- [ ] The solution is the simplest valid one.
- [ ] The diff maps directly to the request.
- [ ] Verification steps and outcomes are documented.
