# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists: it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. In multi-context repos, also check `packages/<package>/docs/adr/` for package-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

This repo is **single-context**: one `CONTEXT.md` and one `docs/adr/` at the root cover
all three packages (`bibbidi`, `bibbidi_runic`, `bibbidi_playwright_trace`).

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-example-decision.md
│   └── 0002-another-decision.md
└── packages/
    ├── bibbidi/lib/
    ├── bibbidi_runic/lib/
    └── bibbidi_playwright_trace/lib/
```

If the packages ever diverge enough to need their own glossaries, switch to multi-context
(a root `CONTEXT-MAP.md` plus a `CONTEXT.md` and `docs/adr/` inside each package):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── packages/
    ├── bibbidi/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← package-specific decisions
    └── bibbidi_runic/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
