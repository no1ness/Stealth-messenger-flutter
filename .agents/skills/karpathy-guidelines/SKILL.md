---
name: karpathy-guidelines
description: Behavioral coding guardrails based on Andrej Karpathy's observations. Use when implementing, reviewing, or refactoring code to avoid hidden assumptions, overengineering, broad diffs, and unverifiable outcomes.
license: MIT
---

# Karpathy Guidelines

Behavioral guidelines to reduce common LLM coding mistakes.

## 1) Think Before Coding

- State assumptions explicitly.
- If requirements are ambiguous, ask before implementing.
- If multiple valid interpretations exist, present options briefly.
- If a simpler path exists, recommend it.

## 2) Simplicity First

- Implement only what was requested.
- Avoid speculative abstractions and future-proofing.
- Prefer the smallest working change.
- If the solution feels too complex, simplify before continuing.

## 3) Surgical Changes

- Touch only files and lines needed for the task.
- Do not perform drive-by refactors or style rewrites.
- Keep existing conventions unless the task requires otherwise.
- Clean up only artifacts introduced by your own change.

## 4) Goal-Driven Execution

- Define clear success criteria before coding.
- Prefer reproducible verification (tests, checks, deterministic steps).
- For multi-step work, plan with per-step verification.
- Stop only after success criteria are met or a clear blocker is reported.

## Quick Verification Checklist

- Did I avoid silent assumptions?
- Is this the simplest valid implementation?
- Does every changed line map to the request?
- Is the result verified with concrete checks?
