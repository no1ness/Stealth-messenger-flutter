---
name: karpathy-origin
description: Karpathy-style execution guardrails adapted for this WordPress + Timber project. Use when editing theme modules, Twig templates, routes, controllers, and integrations to keep assumptions explicit, changes minimal, and outcomes verifiable.
license: MIT
---

# Karpathy Guidelines for Origin Theme

Project-adapted rules for `sait-tehnologii-mebeli`.

## 1) Think Before Coding (Project Context)

- Confirm where the change belongs before editing:
  - module bootstrap/registration: `App/Modules/*`
  - data preparation: `App/.../Http`, services, builders, DTOs
  - rendering: `views/**/*.twig`
- If requirement is ambiguous (route vs template vs module ownership), ask first.
- If two paths are possible, prefer the one matching existing module boundaries.

## 2) Simplicity First (WordPress + Timber)

- Prefer straightforward WordPress/Timber patterns already used in the codebase.
- Do not add new abstraction layers unless repeated usage justifies it.
- Keep Twig dumb: move business/data shaping to PHP controllers/services.
- Reuse existing component APIs (`element`, `wrap`, `component`, `block`) when available.

## 3) Surgical Changes (Theme Safety)

- Change only files required by the request; avoid unrelated cleanups.
- Do not reformat adjacent Twig/PHP blocks unless necessary for the fix.
- Do not alter module registry, CPT registration, or routing unless the task explicitly requires it.
- Remove only dead code introduced by your own edits.

## 4) Goal-Driven Execution (Verification)

- Define success criteria tied to user-visible behavior or route/template output.
- Verify with the narrowest relevant checks (targeted lint/test/manual route check).
- For multi-step work, use:

1. [Step] -> verify: [specific check]
2. [Step] -> verify: [specific check]
3. [Step] -> verify: [specific check]

- Finish only after checks pass or a concrete blocker is documented.

## Project Checklist

- Follows `docs/controller.md` and `docs/architecture.md`.
- Keeps SoC: data in PHP, presentation in Twig.
- Uses existing module/component patterns.
- Keeps diff minimal and request-scoped.
