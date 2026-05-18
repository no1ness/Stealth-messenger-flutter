# Active Plan: (none)

No active fast plan.

`.ai-factory/PLAN.md` is the **fast-plan slot** — `/aif-plan fast <description>` overwrites it freely. If you see content above this comment block, treat it as a transient plan in flight and reconcile before starting a new one.

## Where things live

- **Architectural goal-doc:** [`docs/local-first.md`](../docs/local-first.md) — the evergreen Local-First Stealth contract (Цель, Project rule, Shipped log).
- **Milestone tracker:** [`.ai-factory/ROADMAP.md`](./ROADMAP.md) — sealed / in-flight / committed-not-started milestones with status legend.
- **Active full-mode plans:** [`.ai-factory/plans/`](./plans/) — long-lived branch-scoped plans created by `/aif-plan full`.
- **Bug-fix plans:** `.ai-factory/FIX_PLAN.md` (if present) — owned by `/aif-fix`.

## Starting a new fast plan

```
/aif-plan fast <one-line description>
```

This will overwrite the content of this file. The architectural goal-doc and roadmap are unaffected — they live elsewhere.
