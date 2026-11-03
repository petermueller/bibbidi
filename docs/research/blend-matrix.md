# Research: `blend` for a local optional-dep test matrix

Resolves [#12](https://github.com/petermueller/bibbidi/issues/12) (part of map
[#7](https://github.com/petermueller/bibbidi/issues/7)). Researched 2026-11-02 against
blend 0.5.0, Elixir 1.19.4 / OTP 28, muontrap 2.0.1, net_runner 1.6.0.

These are findings, not decisions. How Bibbidi models dep absence, gates adapter tests,
and runs the matrix is settled in
[#18](https://github.com/petermueller/bibbidi/issues/18); see "Open questions for #18".

## Question

How does the `blend` library work, and what does it offer for running Bibbidi's full
suite (`mix test.all` from `packages/bibbidi/`, Firefox integration included) locally
against every optional-dep combination: no optional deps / `muontrap` / `net_runner`?

## Short answer

- blend generates and maintains **one lockfile (plus its own `deps/` and `_build/`) per
  named variation**, and gives you a `BLEND=<name>` env var that points Mix at that
  lockfile. That is all it does. At `BLEND=x mix test` time the dependency *list* is
  still whatever `mix.exs` returns; only the resolved versions and the build/deps paths
  change.
- Consequently **blend cannot express "dep absent"**. A blend entry can add a dep or
  replace an existing dep's tuple (version pin, options), never remove one, and even an
  added/replaced tuple only influences lockfile resolution, not the run. Verified in a
  scratch project (see "Experiments").
- Absence therefore has to come from `mix.exs` itself. It is feasible for `mix.exs` to
  vary its deps list on the active blend (verified, with caveats in §3); whether Bibbidi
  does that, and whether blend is worth adding at all once the deps list varies, is a
  design choice (see "Open questions").
- `mix test.all` (alias for `test --include integration`) composes with `BLEND=...`
  unchanged. One ExUnit fact matters for adapter tests: `--include integration` overrides
  *every* `exclude` (§5).

## Sources

Primary, read in full unless noted:

- hex.pm package metadata: <https://hex.pm/api/packages/blend> (latest 0.5.0, 2025-03-17;
  canonical repo link `https://github.com/mimiquate/blend`; hexdocs at
  <https://hexdocs.pm/blend>, which is the README only: `docs: [main: "readme", extras: ["README.md"]]` in blend's `mix.exs`).
- blend repo, `main` branch (last push 2026-10-01):
  - `README.md` — blend.exs format, `mix blend.get`, Option A (`cp` the lockfile) vs
    Option B (`BLEND` env var + `blend/premix.exs` + `maybe_lockfile_option`), task list.
  - `CHANGELOG.md` — 0.5.0 moved layout to `blend/<name>/{mix.lock,deps,_build}`.
  - `lib/blend.ex` — `Blend.within/2` (how a blend's deps are merged: `List.keystore/4`
    on the host project's `:deps`, then `lockfile:`, `build_path:`, `deps_path:` pushed
    on the project stack), `Blend.blends/0` (`Code.eval_string` of `blend.exs`, must
    return a map).
  - `lib/mix/tasks/blend/{get,update,clean,list}.ex` — each is `Blend.within(blend, fn ->
    Mix.Task.rerun("deps.get" | "deps.update" | "clean --deps", args) end)` over every
    blend; `list` prints map keys.
  - `lib/blend/templates/premix.exs` — reads `BLEND`, `Map.fetch!`s it from `blend.exs`
    (so a typo raises `KeyError`), then `System.put_env` for `MIX_LOCKFILE`,
    `MIX_DEPS_PATH`, `MIX_BUILD_ROOT` unless already set.
  - `.github/workflows/ci.yml` — blend's own CI (Elixir/OTP matrix only; does not use
    blends itself).
- `elixir-waffle/waffle_gcs`, `main` branch, the reference user:
  - `blend.exs` — five version-pin blends with a long header comment.
  - `mix.exs` — the premix compile at the top, `|> Keyword.merge(maybe_lockfile_option())`,
    `{:blend, "~> 0.5.0", only: :dev}`, `"test.unit": ["test --exclude integration"]`.
  - `blend/` — `premix.exs` + one `<name>/mix.lock` per blend (deps/_build gitignored:
    `/blend/*/deps/`, `/blend/*/_build/`).
  - `test/test_helper.exs` — detects the goth version via `Application.load(:goth)` +
    `Application.spec(:goth, :vsn)` and widens `ExUnit.configure(exclude: ...)` for old-goth
    blends; comments note a second `exclude:` replaces rather than merges.
  - `.github/workflows/elixir.yml` — `env: BLEND: ${{ matrix.blend }}`, `include:` matrix
    rows mixing Elixir/OTP rows and blend rows, per-blend deps cache keyed on
    `blend/<name>/mix.lock`, an `audit` job running `mix blend.get && git diff --exit-code blend.exs blend/`.
- Mix moduledoc, "Environment variables" section (`Code.fetch_docs(Mix)`, Elixir 1.19.4):
  `MIX_BUILD_ROOT`, `MIX_DEPS_PATH`, `MIX_EXS` are read by Mix natively; there is **no**
  `MIX_LOCKFILE` variable, which is why blend asks you to add `maybe_lockfile_option/0`.
- hex.pm release metadata: `muontrap` 2.0.1 (requires `elixir_make ~> 0.6`, build tools
  mix+make, Elixir `~> 1.11`); `net_runner` 1.6.0 (requires `elixir_make ~> 0.10.0`,
  mix+make, Elixir `~> 1.17`).
- `actions/runner-images` `images/ubuntu/Ubuntu2404-Readme.md`: lists Mozilla Firefox
  158.0.1 and Geckodriver 0.37.1 preinstalled as of 2026-11-02.
- This repo: `CLAUDE.md` (Testing, `BBD_*` env vars), `packages/bibbidi/mix.exs`
  (`"test.all": ["test --include integration"]`, `cli/0` `preferred_envs`, `package.files`
  does not include `blend.exs`), `packages/bibbidi/test/test_helper.exs`
  (`ExUnit.start(exclude: [:integration])`), `test/support/integration_case.ex`
  (`@moduletag :integration` via `use Bibbidi.IntegrationCase`).

Experiments: two throwaway projects in this session's scratchpad (not committed).
`blendlab` used `decimal` and `nimble_options` as stand-ins for the two native deps so
compiles stayed fast; `natlab` compiled the real `muontrap` and `net_runner`.

## Findings

### 1. `blend.exs` format

A plain Elixir file whose last expression is a map: `%{blend_name: [dep_tuples]}`
(`Blend.blends/0` raises if it is not a map). Keys name the blend and become the
directory `blend/<name>/`; values are ordinary Mix dep tuples that are merged over the
host project's deps with `List.keystore(deps, app, 0, dep)` (`Blend.within/2`), so a
tuple whose app already exists in `mix.exs` *replaces* that tuple wholesale, and a new
app is *appended*. Empty lists are legal (verified). waffle_gcs documents each blend's
purpose in a header comment.

### 2. `mix blend.get` and running under a blend

- `mix blend.install` writes a commented template `blend.exs`. `mix blend.gen.premix`
  writes `blend/premix.exs`.
- `mix blend.get` iterates every blend and runs `deps.get` inside `Blend.within/2`, which
  resolves `host deps + overrides` to `blend/<name>/mix.lock` and fetches sources into
  `blend/<name>/deps`. Each blend therefore has a **full private copy of `deps/` and a
  private `_build/`** (disk and compile time scale with blend count; all of Bibbidi's
  deps compile once per blend).
- Selecting a blend at run time is **`BLEND=<name>`**, nothing else: `blend/premix.exs`,
  compiled at the top of `mix.exs`, sets `MIX_LOCKFILE=blend/<name>/mix.lock`,
  `MIX_DEPS_PATH=blend/<name>/deps`, `MIX_BUILD_ROOT=blend/<name>/_build`. Mix consumes
  the last two natively; the first is consumed by the `maybe_lockfile_option/0` you add
  to `project/0`. `MIX_EXS` is not involved; the same `mix.exs` is used for every blend.
- Option A in the README (`cp blend/<name>/mix.lock mix.lock`) is the no-glue
  alternative; it shares `deps/`/`_build/` with the main lock.
- Verified in `blendlab`: `BLEND=decimal_2_1 mix test.all` reported
  `lockfile opt="blend/decimal_2_1/mix.lock"`, `build_path=blend/decimal_2_1/_build/test`,
  `deps_path=blend/decimal_2_1/deps`, `decimal vsn=2.1.1` while the main lock had 2.4.1;
  the `test.all` alias and its `:test` preferred env applied unchanged.
- Paths in `premix.exs`, `blend.exs` and the `File.exists?("blend/premix.exs")` check are
  cwd-relative, so everything must run from `packages/bibbidi/` (already the rule in
  `CLAUDE.md`).

### 3. "Dep absent" vs "dep pinned to a version"

blend only models **pinned**. Verified behaviours (`blendlab`):

| blend override | lockfile | at `BLEND=x mix test` |
|---|---|---|
| `[{:decimal, "2.1.1"}]` (inside the `mix.exs` requirement) | decimal 2.1.1 | decimal 2.1.1 compiled and loaded — the intended use |
| `[{:decimal, "~> 1.9"}]` (outside `~> 2.0`) | decimal 1.9.0 | **fails**: `the dependency does not match the requirement "~> 2.0", got "1.9.0"` — `mix.exs` still owns the requirement |
| `[{:jason, "~> 1.4"}]` (not in `mix.exs`) | jason added | `Code.ensure_loaded?(Jason) == false`; lock entry inert — the deps list is still `mix.exs`'s |
| `[{:decimal, "~> 2.0", only: :never}]` (attempt to exclude) | decimal present | decimal compiled and loaded — the override only affected resolution |

So absence has to come from `mix.exs`. Verified facts about doing that:

- `premix.exs` runs before `project/0` and `BLEND` is in the environment, so `deps/0`
  *can* branch on `System.get_env("BLEND")`. In `blendlab`, a `BLEND=no_native` run gave
  `deps in mix.exs=[:blend]`, `Decimal loaded?=false`, `lib dirs=["blendlab"]` (nothing
  else in `_build/test/lib`); `BLEND=decimal` and `BLEND=nimble` each had exactly their
  one optional dep.
- Because each blend owns its `_build`, switching blends does not leave stale compile-time
  `Code.ensure_loaded?/1` decisions behind (no `mix compile --force` needed).
- **Consumers see the env.** Mix evaluates a *dependency's* `mix.exs` with the consumer's
  environment: a path dep printed `BLEND="consumer_blend"` while its `cwd` was
  `deps/<app>` and `File.exists?("blend.exs")` was `false`. A consumer who uses blend
  themselves would therefore see Bibbidi's `deps/0` run with *their* `BLEND` value. Any
  blend-dependent `deps/0` needs a guard that distinguishes "Bibbidi being developed" from
  "Bibbidi as a dep" (e.g. a file that is not in `package.files`) and must not raise on
  unknown names.
- With a blend-dependent deps list the blend entries themselves carry no information
  (`%{no_native: [], muontrap: [], net_runner: []}`). What blend still provides: the
  per-blend `mix.lock`/`deps`/`_build` layout, `premix.exs`, `mix blend.list`,
  `mix blend.clean`, and vocabulary parity with waffle_gcs. The same layout is roughly 30
  lines of Mix plumbing if hand-rolled.
- **Lockfile wrinkle** (verified): `mix blend.get` runs with `BLEND` unset, so the host
  deps are the *full* set and every blend's lockfile lists every optional dep. The extra
  entries are inert at test time (`BLEND=nimble mix test.all` ran fine with an unused
  decimal entry), but `mix deps.unlock --check-unused` fails under such a blend, and
  `mix blend.get` re-adds the entries after you prune them (so a waffle_gcs-style
  `mix blend.get && git diff --exit-code` drift check would churn). Alternative verified:
  seed `blend/<name>/mix.lock` from `mix.lock`, then `BLEND=<name> mix deps.get` and
  `BLEND=<name> mix deps.unlock --unused`, which yields the main lock's versions minus
  the absent deps (`nimble_options` entry byte-identical, `decimal` dropped).

### 4. Signals available to `test_helper.exs`

Three ways a test helper can learn what is present, all verified at `test_helper.exs`
time:

- `System.get_env("BLEND")` — the blend name (`nil` on the main lock). Reflects what the
  blend *promises*.
- `Code.ensure_loaded?(MuonTrap)` / `Code.ensure_loaded?(NetRunner)` — `true` only when the
  dep is compiled into the active `_build`; works because deps are on the code path before
  `test_helper.exs` runs. Reflects what is *actually* present, and is meaningful on the
  main lock too.
- `Application.load(:muontrap); Application.spec(:muontrap, :vsn)` — waffle_gcs's version
  check; `nil` when absent.

ExUnit facts: `exclude:` is set once; a second `ExUnit.configure(exclude: ...)` replaces
it (waffle_gcs's comment). `ExUnit.start/1` opts are merged with Mix's CLI opts, so
`--include integration` from the alias survives, as it does today.

### 5. Does `mix test.all` / `--include integration` compose?

Yes for running: `BLEND=<name> mix test.all` picks up the alias, the `:test` preferred
env and the blend paths. The `BBD_*` variables are orthogonal and keep working
(`BBD_BROWSER_URL`, `BBD_DEBUG`).

One ExUnit rule bites adapter tests (verified): a test that matches an **include** runs
even if it also matches an **exclude**. With `--include integration`, a test tagged
`:integration` + `:muontrap` runs under a blend without muontrap despite
`exclude: [:muontrap]`; in `blendlab` the unguarded module ran and failed with
`module Decimal is not available`. An exclude is enough for tests that carry no included
tag, but not for adapter *integration* tests. Also verified: a module-level
`@moduletag skip: "..."` is honoured regardless of include/exclude filters (the guarded
module reported `1 skipped` under the absent blend and ran under the present one). How
Bibbidi uses these facts is an open question below.

### 6. CI facts (for later; the repo has no workflows yet)

- waffle_gcs's pattern: `env: BLEND: ${{ matrix.blend }}` at job level,
  `strategy.matrix.include` rows where some rows set `blend`, `fail-fast: false`, a deps
  cache per blend keyed on `hashFiles('blend/<name>/mix.lock')` with path
  `blend/<name>/deps`, and an `audit` job that re-runs `mix blend.get` and diffs.
- `mix deps.get` under `BLEND` writes/reads the blend's lockfile and `deps/` directly, so
  a workflow does not need `mix blend.get`.
- The `ubuntu-24.04` runner image ships Firefox (158.0.1 at time of writing) and
  `geckodriver`; headless is the default without `BBD_DEBUG`.
- Both native deps need `make` and a C compiler; the Ubuntu image has them. `net_runner`
  requires Elixir `~> 1.17`, inside Bibbidi's `~> 1.19` floor.
- A `mix blend.get` drift check only works if the lockfiles are what `mix blend.get`
  produces (see the wrinkle in §3).

## Gotchas (facts)

1. **blend never removes a dep.** Overrides are `List.keystore/4` merges used only for
   lockfile resolution; the run-time deps list is `mix.exs`'s. (§3)
2. **Pins outside the `mix.exs` requirement fail at run time** with "does not match the
   requirement". Irrelevant to a presence matrix; relevant if a version blend is added
   later. (§3)
3. **`--include integration` beats every `exclude`**; `@moduletag skip:` beats both. (§5)
4. **`mix blend.get` with a blend-dependent deps list** writes every optional dep into
   every lockfile and re-adds them after `deps.unlock --unused`. (§3)
5. **Consumers see your `BLEND`.** A dep's `mix.exs` is evaluated with the consumer's env.
   (§3)
6. **`BLEND=typo` raises `KeyError`** from `premix.exs` (`Map.fetch!`), before any task runs.
7. **`BLEND` is not a `BBD_*` variable.** `CLAUDE.md` says all project env vars use the
   `BBD_` prefix; `BLEND` is blend's own, hardcoded in the generated `premix.exs`
   (regenerated by `mix blend.gen.premix`).
8. **Disk and compile time scale with blends.** Each blend has a full `deps/` copy and
   its own `_build/`; all Bibbidi deps compile per blend, and `muontrap`/`net_runner`
   each compile C (`elixir_make`) in their blend. Both built cleanly on this Mac
   (`priv/muontrap` port binary; `priv/shepherd` + `priv/net_runner_nif.so`).
9. **Everything is cwd-relative.** Run from `packages/bibbidi/`; `premix.exs` and
   `blend.exs` are looked up relative to the current directory.
10. **`premix.exs` only sets variables that are unset**, so an exported `MIX_BUILD_ROOT`
    or `MIX_DEPS_PATH` in the shell silently wins over the blend's paths.
11. **`mix blend.clean` removes stale lockfiles only**, not stale `blend/<old>/` dirs or
    their `deps/`/`_build/`; delete those by hand when a blend is renamed.
12. `MIX_DEPS_PATH` is documented as "an absolute path"; blend sets a relative one and
    Mix resolves it fine today (`Mix.Project.deps_path/0` returned the absolute path).
    Noted in case a future Mix tightens this.
13. **A plain `aliases:` entry cannot set env vars per step**, so a one-command
    "run every blend" needs a Mix task or a shell script.

## Open questions for #18

Design choices this research surfaces but does not make:

1. **blend or hand-rolled?** Once `mix.exs` owns absence, blend only contributes layout,
   `premix.exs` and two Mix tasks (§3). Is parity with waffle_gcs worth the dependency?
2. **How does `mix.exs` model absence?** Branch `deps/0` on `BLEND` (verified feasible),
   or some other mechanism? What is the guard that protects consumers who evaluate
   Bibbidi's `mix.exs` with their own `BLEND` set (§3), and what does an unknown blend
   name do?
3. **How do adapter tests gate on presence?** Exclude tags computed in `test_helper.exs`
   (insufficient alone for integration tests, §5), module-level `@moduletag skip:` in
   each adapter test module, a shared case template that takes the dep module, or
   conditional compilation of the adapter modules in `lib/` so the tests target the
   adapter rather than the dep? Which signal from §4 drives it?
4. **Which matrix rows?** Main lock (everything present) plus one blend per absence
   combination, or fewer?
5. **How are per-blend lockfiles produced and kept honest?** `mix blend.get` (inert
   surplus entries, no drift check), seeded `deps.get` + `deps.unlock --unused` (versions
   match the main lock), or something else?
6. **Env var naming.** Accept `BLEND` as a documented exception to the `BBD_` rule, or
   hand-maintain `premix.exs` with a `BBD_BLEND` alias (gotcha 7)?
7. **One-command matrix run.** Mix task, shell script, or just documented commands
   (gotcha 13)?
