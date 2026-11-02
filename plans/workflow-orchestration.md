# Workflow Orchestration / Repair Framework

A theoretical workflow orchestration / repair framework — a **WorkflowUse-alternative** — would sit on top of bobbidi to enable record-once-replay-forever workflows with LLM-based repair when they break.

This plan captures what bobbidi must export to make that framework buildable in roughly 2k LOC, and what the framework should NOT replicate from existing libraries (browser-use, browser-harness, workflow-use).

**Bobbidi itself is NOT the orchestration framework.** Bobbidi provides the substrate; the framework is a separate package.

## Why this matters

The "company-builds-workflow-tool-in-Elixir" leverage is differentiated only if bobbidi exposes the right primitives. Without those primitives, the orchestration framework reimplements DOM serialization, selector strategy generation, recorder transport, and actionability checks — all things bobbidi naturally absorbs.

The existing PoC in this monorepo (`packages/playbook` + `packages/autopilot`) is the seed: a contractor ported a Python implementation to use bibbidi. Once bobbidi ships, the orchestration framework re-emerges as a dramatically smaller layer on top, with bobbidi taking on the hand-rolled DOM/JS/event work that's currently scattered across both packages.

## What the framework needs from bobbidi

1. **Indexed-DOM snapshot** (`Bobbidi.Snapshot.capture/2`) with role/text/bbox/selector/visible/enabled/shared_ref per element. Generation id for staleness. `Locator.snapshot_index(snapshot, n)` resolution. — *Phase 1 of bobbidi.*
2. **Page event bridge** (`Bobbidi.Bridge.install/2` + `subscribe/3`) using `script.message` channels — no `console.log` markers, no globals. `%Bobbidi.Recorded.*{}` structs (Click, Input, Submit, Navigation, KeyPress, FocusChange) for the recorder format. — *Phase 1.*
3. **Selector strategy generation as pure functions** (`Bobbidi.Selector.Strategy.from_element/1`): given a `Bobbidi.Snapshot.Element`, return `[{kind, value, priority}]` covering id / test_id / aria_label / role+text / text_exact / placeholder / xpath. Pure, deterministic, no LLM. Used at record time to capture multiple identification strategies per step. — *Phase 2.*
4. **Markdown extraction** (`Bobbidi.Capture.markdown/2`): clean text representation of a page or element subtree. Workflow-use's lightweight alternative to LLM extraction for "read the page" steps. — *Phase 1 if cheap, Phase 2 otherwise.*
5. **AX-tree access** (`Bobbidi.Accessibility.tree/2`) for semantic role/name extraction beyond what `BrowsingContext.LocateNodes` provides. — *Phase 2.*
6. **Network observation primitives** (`Bobbidi.Network.{wait_for_response, route, on_request, on_response}`). Workflows that wait on specific API calls or mock them during replay. — *Phase 2.*
7. **Cheap dialog observer**: subscribe to `BrowsingContext.UserPromptOpened`, accept/dismiss, surface as a recorded event. — *Phase 2-3.*
8. **Per-action timeouts** — an action that hangs blocks the workflow forever otherwise. — *Phase 1.*
9. **Tab management** — workflows often span tabs. — *Phase 1.*
10. **Pure-data steps**. All bobbidi action arguments and return values must be serializable: locators (struct of structs), sessions (no pids in nested fields except top-level conn), snapshots, recorded events. The framework can pickle any sequence of bobbidi calls. — *Constraint maintained throughout bobbidi development.*

## Framework architecture

### Workflow definition (the artifact)

```elixir
%MyOrchestrator.Workflow{
  name: "Login flow",
  inputs: %{username: :string, password: :string},
  steps: [
    %Step.Navigate{url: "https://app.example.com/login"},
    %Step.Fill{
      target: %Target{
        primary: {:test_id, "username"},
        fallbacks: [
          {:label, "Email"},
          {:placeholder, "you@example.com"},
          {:xpath, "//input[1]"}
        ],
        text_at_record: "you@example.com",
        bbox_at_record: {180, 240, 320, 32}
      },
      value: {:input, :username}
    },
    %Step.Fill{target: ..., value: {:input, :password}},
    %Step.Click{target: ..., expects: :navigation},
    %Step.Expect{matcher: %Expect.Url{contains: "/dashboard"}},
    %Step.Extract{target: ..., into: :user_id, format: :text}
  ]
}
```

### Recording

1. `Bobbidi.Bridge.install/2` registers a channel.
2. Each `%Bobbidi.Recorded.X{}` event arrives in the orchestrator's pid.
3. Orchestrator captures a snapshot at each event ts (or debounced).
4. For each event's `target`, runs `Bobbidi.Selector.Strategy.from_element/1` to produce ordered fallbacks.
5. Synthesizes a `%Step.X{}` with primary + fallbacks + text + bbox.

### Replay

1. For each step, try the primary target; if that fails, walk fallbacks in priority order.
2. Apply `Bobbidi.click/2` / `Bobbidi.fill/3` etc. with auto-wait.
3. If all fallbacks fail and `repair_with: :llm` is set, dispatch to the repair pipeline.

### Repair

1. Capture current snapshot + screenshot.
2. Diff against the recorded step's `text_at_record` / `bbox_at_record` / strategies.
3. Send to LLM with: failed step description, current snapshot, original task.
4. LLM emits a corrected `%Step.X{}` (structured output).
5. Validator checks the corrected step matches at least one element via locator resolution before adopting.
6. Retry; if successful, persist the corrected step back to the workflow definition.

The repair primitive is just "rebuild the step against the current page state" — exactly workflow-use's healing pattern (`workflow-use/workflows/workflow_use/healing/service.py:276-329`). The advantage of doing this in Elixir on bobbidi: snapshot + selector-strategy generation are pure functions, deterministic, easy to test.

## Things to NOT replicate from browser-use / workflow-use / browser-harness

1. **Validator hard-rule that "every workflow must end with extract"** (workflow-use `schema/views.py:240-258`). Strange product opinion masquerading as schema validation. Workflows can end however the user wants.
2. **Agent-step-inside-deterministic-workflow** (`AgenticWorkflowStep` in workflow-use, `workflow/service.py:329`). 10-30x slower; the prompt itself yells `"NEVER use agent steps for simple click/input"` (`healing/prompts/workflow_creation_prompt.md:18-20`). It's a code-smell escape hatch nobody actually wants. Provide LLM repair as a separate concern; don't bake "agent step type" into the workflow DSL.
3. **`Tools.__getattr__` magic** (browser-use `tools/service.py:2193-2249`) for runtime-creating Pydantic models. Elixir's compile-time struct + protocol is cleaner; don't try to imitate.
4. **Bus-of-everything event system** (browser-use `browser/events.py`, 50+ event classes through one bus). Forces every action through dispatch. Direct bobbidi calls + selective subscribe is leaner.
5. **Chrome-extension-as-recorder** (workflow-use `extension/src/`). Bobbidi.Bridge via BiDi `script.message` is strictly better — no extension install, cross-browser, persists across navigations.
6. **Markdown-only extraction at workflow end**. Provide markdown, html, AX-tree, structured-from-locator extraction as equal options; let users pick.
7. **`Promise.all([click, waitForNavigation])` race idioms** (Puppeteer-style). Auto-wait + explicit `Bobbidi.Expect.url/3` is clearer.
8. **Live-edit helpers file from agent** (browser-harness's "agent writes its own python helpers" model). Brilliant for a CLI agent, terrible for a library API. The orchestration framework should be typed, structured, replayable.

## Out of scope for bobbidi (belongs in the framework)

- Workflow definition schema
- Variable resolution (1Password, env vars, file, vault, prompt) — pattern already in `playbook/runner.ex:64-134`, port to the framework
- Conditional steps and step gating
- Repair LLM dispatch and prompts
- Workflow validation / linting
- Workflow persistence (YAML / JSON / sqlite)
- Multi-workflow orchestration / scheduling
- "Run this hourly and notify me when it breaks" scheduling

## Phasing relative to bobbidi

| Bobbidi phase | Framework can ship |
|---|---|
| Phase 1 | Recording (bridge events) + replay-with-bobbidi-actions for click/fill/navigate. No repair. Variable resolution. Per-call timeouts. |
| Phase 2 (selector strategies, network, AX) | Repair (LLM-driven) using pure-function strategy fallback + LLM-regenerated steps. Network mocking for replay. AX-tree for richer LLM context. |
| Phase 3 | Production-grade: dialog handling, advanced wait strategies, multi-tab workflows, scheduling. |

## Reference implementations to study

| Library | Where it lives | Useful for |
|---|---|---|
| browser-use | `/Users/peter/work/browser-use/` | LLM tool-call shape (indexed DOM + ActionModel JSON), system-prompt design, retry patterns |
| workflow-use | `/Users/peter/work/workflow-use/` | Workflow schema, recorder format, healing service, selector strategy generation |
| browser-harness | `/Users/peter/work/browser-harness/` | Anti-framework lessons (what NOT to abstract), CDP primitive map, daemon design |
| playbook (existing PoC) | `/Users/peter/work/bibbidi/packages/playbook/` | Existing recorder + transcriber + runner, the seed for the Elixir-side framework |
| autopilot (existing PoC) | `/Users/peter/work/bibbidi/packages/autopilot/` | Existing browser action surface, vision integration, agent loop |

## References

- browser-use repo + cloud notes: https://docs.browser-use.com/llms-full.txt
- workflow-use repo: `/Users/peter/work/workflow-use/`
- browser-harness repo: `/Users/peter/work/browser-harness/`
- Existing PoC: `/Users/peter/work/bibbidi/packages/playbook/` and `packages/autopilot/`
- Selector generator reference: `workflow-use/workflows/workflow_use/healing/selector_generator.py:47`
- LLM repair prompt reference: `workflow-use/workflows/workflow_use/healing/prompts/workflow_creation_prompt.md`
- `plans/bobbidi.md` — bobbidi primitives this framework consumes
