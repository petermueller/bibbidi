# Research: `blend` for a local optional-dep test matrix

Resolves [#12](https://github.com/petermueller/bibbidi/issues/12) (part of map
[#7](https://github.com/petermueller/bibbidi/issues/7)). Researched 2026-11-02 against
blend 0.5.0, Elixir 1.19.4 / OTP 28, muontrap 2.0.1, net_runner 1.6.0.

## Question

How does the `blend` library work, and how would it run Bibbidi's full suite
(`mix test.all` from `packages/bibbidi/`, Firefox integration included) locally against
every optional-dep combination: no optional deps / `muontrap` / `net_runner`?

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
- For Bibbidi's matrix the deps list itself has to vary. The workable design is:
  `mix.exs` chooses which `optional: true` deps to declare based on the active blend
  (`System.get_env("BLEND")`, guarded so consumers are unaffected), and blend supplies
  the per-blend lockfile, `deps/`, `_build/` isolation and the `BLEND` plumbing. The
  three blends in `blend.exs` are then just names with empty override lists.
- `mix test.all` (alias for `test --include integration`) composes with `BLEND=...`
  unchanged. One ExUnit subtlety: `--include integration` overrides *every* `exclude`, so
  adapter tests that are also integration tests must be skipped with a module-level
  `@moduletag skip:` guard, not via `ExUnit.start(exclude: ...)`.
- Local matrix = four runs: `mix test.all` (main lock, every optional dep present) plus
  `BLEND=<name> mix test.all` for each of `no_native`, `muontrap`, `net_runner`.

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
- `actions/runner-images` `images/ubuntu/Ubuntu2404-Readme.md` (for the CI note): lists
  Mozilla Firefox 158.0.1 and Geckodriver 0.37.1 preinstalled as of 2026-11-02.
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
purpose in a header comment; worth copying.

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
  alternative; it shares `deps/`/`_build/` with the main lock, so it is only sensible as
  a throwaway CI step.
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

So absence has to come from `mix.exs`. The deps list can branch on the active blend
because `premix.exs` runs before `project/0` and `BLEND` is in the environment anyway:

```elixir
defp deps do
  [ ...fixed deps... ] ++ optional_deps(active_blend())
end

defp optional_deps("no_native"), do: []
defp optional_deps("muontrap"), do: [@optional_deps.muontrap]
defp optional_deps("net_runner"), do: [@optional_deps.net_runner]
defp optional_deps(_), do: Map.values(@optional_deps)   # nil / unknown => everything
```

Verified: `BLEND=no_native mix test.all` gave `deps in mix.exs=[:blend]`,
`Decimal loaded?=false`, `lib dirs=["blendlab"]` (nothing else in `_build/test/lib`);
`BLEND=decimal` and `BLEND=nimble` each had exactly their one optional dep. Because each
blend owns its `_build`, switching blends never leaves stale compile-time
`Code.ensure_loaded?/1` decisions in adapter modules behind (no `mix compile --force`
needed).

The fallback clause is load-bearing. Mix evaluates a *dependency's* `mix.exs` with the
consumer's environment: verified with a path dep that printed
`BLEND="consumer_blend"` while its `cwd` was `deps/<app>` and `File.exists?("blend.exs")`
was `false`. A consumer who happens to use blend themselves must still get Bibbidi's full
optional-dep list, so gate on `File.exists?("blend.exs")` (not in `package.files`) and
never raise on unknown names.

With a blend-dependent deps list the blend entries themselves carry no information;
`blend.exs` becomes `%{no_native: [], muontrap: [], net_runner: []}`. What blend still
buys: the per-blend `mix.lock`/`deps`/`_build` layout, `premix.exs`, `mix blend.list`,
`mix blend.clean`, and parity with the waffle_gcs vocabulary. It is roughly 30 lines of
Mix plumbing that could be hand-rolled; the recommendation is to use blend anyway so the
layout and commands match the reference project and the later CI sketch.

Lockfile generation under this design has a wrinkle (verified): `mix blend.get` runs with
`BLEND` unset, so the host deps are the *full* set and every blend's lockfile lists every
optional dep. The extra entries are inert at test time (`BLEND=nimble mix test.all` ran
fine with an unused decimal entry) but `mix deps.unlock --check-unused` fails under such a
blend, and `mix blend.get` re-adds the entries after you prune them (so a waffle_gcs-style
`mix blend.get && git diff --exit-code` drift check would churn). Two clean options:

- **Seeded per-blend `deps.get` (recommended)**: copy `mix.lock` into
  `blend/<name>/mix.lock`, then `BLEND=<name> mix deps.get` and
  `BLEND=<name> mix deps.unlock --unused`. Result: identical versions to the main lock
  minus the absent deps, so presence is the only variable across the matrix. Verified
  (`nimble_options` entry byte-identical to the main lock, `decimal` dropped).
- `mix blend.get` as documented: one command, fresh resolution per blend (versions may
  drift from the main lock), inert surplus entries. Acceptable if nobody runs
  `--check-unused` under a blend.

### 4. How `test_helper.exs` learns what is present

Three signals, all verified at `test_helper.exs` time:

- `System.get_env("BLEND")` — the blend name (`nil` on the main lock).
- `Code.ensure_loaded?(MuonTrap)` / `Code.ensure_loaded?(NetRunner)` — `true` only when the
  dep is compiled into the active `_build`; works because deps are on the code path before
  `test_helper.exs` runs. This is the robust one: it reflects what is actually present
  rather than what the blend name promises, and it is right on the main lock too.
- `Application.load(:muontrap); Application.spec(:muontrap, :vsn)` — waffle_gcs's version
  check; `nil` when absent.

Bibbidi's helper would become:

```elixir
missing_adapter_tags =
  [{MuonTrap, :muontrap}, {NetRunner, :net_runner}]
  |> Enum.reject(fn {mod, _tag} -> Code.ensure_loaded?(mod) end)
  |> Enum.map(fn {_mod, tag} -> tag end)

ExUnit.start(exclude: [:integration | missing_adapter_tags])
```

(`exclude:` must be set once; a second `ExUnit.configure(exclude: ...)` replaces it, as
waffle_gcs's comment notes. `ExUnit.start/1` opts are merged with Mix's CLI opts, and
`--include integration` from the alias survives, as it does today.)

### 5. Does `mix test.all` / `--include integration` compose?

Yes for running: `BLEND=<name> mix test.all` picks up the alias, the `:test` preferred
env and the blend paths. The `BBD_*` variables are orthogonal and keep working
(`BBD_BROWSER_URL`, `BBD_DEBUG`).

One ExUnit rule bites the adapter tests (verified): a test that matches an **include**
runs even if it also matches an **exclude**. With `--include integration`, an adapter
integration test tagged `:integration` + `:muontrap` runs under `no_native` despite
`exclude: [:muontrap]` — in `blendlab` the unguarded module ran and failed with
`module Decimal is not available`. The exclude is enough for adapter *unit* tests (they
carry no `:integration` tag) but not for adapter *integration* tests. Fix at the module
level with the `skip` tag, which is honoured regardless of filters:

```elixir
defmodule Bibbidi.Launcher.MuonTrapTest do
  use Bibbidi.IntegrationCase          # adds @moduletag :integration
  @moduletag :muontrap

  unless Code.ensure_loaded?(MuonTrap) do
    @moduletag skip: "muontrap is not in this blend"
  end
  ...
end
```

Verified: the guarded module reported `1 skipped` under `BLEND=no_native mix test.all`
and ran under `BLEND=decimal`. If the adapter modules in `lib/` are themselves compiled
conditionally (`if Code.ensure_loaded?(MuonTrap) do defmodule ... end`), the guard can
test the adapter module instead of the dep. Either way the skip belongs in the test
module (or in a `Bibbidi.AdapterCase` template that takes the dep module as an option),
not in `test_helper.exs`.

### 6. CI matrix shape (for later; the repo has no workflows yet)

waffle_gcs's pattern transfers directly: `env: BLEND: ${{ matrix.blend }}` at job level,
`strategy.matrix.include` rows where some rows set `blend`, `fail-fast: false`, and a
deps cache per blend keyed on `hashFiles('blend/<name>/mix.lock')` with path
`blend/<name>/deps`. Bibbidi-specific points:

- One job, four rows: `{ blend: '' }` (main lock), `no_native`, `muontrap`, `net_runner`.
  `mix deps.get` under `BLEND` writes/reads the blend's lockfile and `deps/` directly,
  so the workflow never needs `mix blend.get`.
- Run `mix test.all` rather than `mix test` once Firefox is wanted in CI: the
  `ubuntu-24.04` runner image ships Firefox (158.0.1 at time of writing) and
  `geckodriver`, so no install step; headless is the default without `BBD_DEBUG`.
  Start with unit-only (`mix test`) per #7's "unit-only, then maybe Firefox" note.
- Both native deps need `make` and a C compiler; the Ubuntu image has them. `net_runner`
  requires Elixir `~> 1.17`, which is inside Bibbidi's `~> 1.19` floor.
- A drift check like waffle_gcs's `audit` job only works with the seeded-lockfile recipe
  (option 1 in §3) expressed as a script, not with `mix blend.get` (see the wrinkle in §3).

## Sketch for Bibbidi

Nothing below is applied; `packages/bibbidi/mix.exs` was not changed in this ticket.

### `packages/bibbidi/blend.exs`

```elixir
# Optional-dep presence matrix for the Launcher adapters. Which optional deps each
# blend declares lives in mix.exs (optional_deps/1); blend's job here is the
# per-blend mix.lock + deps/ + _build/ and the BLEND env var (blend/premix.exs).
#
# (no BLEND)  - the main mix.lock: every optional dep present. Plain `mix test`.
# no_native   - neither muontrap nor net_runner. Proves the default Launcher and the
#               adapter modules compile and skip cleanly without their deps.
# muontrap    - muontrap only.
# net_runner  - net_runner only.
#
# Lockfiles are seeded from mix.lock so versions match it; see docs/research/blend-matrix.md.
%{
  no_native: [],
  muontrap: [],
  net_runner: []
}
```

### `packages/bibbidi/mix.exs` delta

```elixir
# top of file, before defmodule
if File.exists?("blend/premix.exs") do
  Code.compile_file("blend/premix.exs")
end

# in project/0
|> Keyword.merge(maybe_lockfile_option())

defp maybe_lockfile_option do
  case System.get_env("MIX_LOCKFILE") do
    nil -> []
    "" -> []
    lockfile -> [lockfile: lockfile]
  end
end

# in deps/0
{:blend, "~> 0.5.0", only: :dev},
# ... existing deps ...
] ++ optional_deps(active_blend())

@optional_deps %{
  muontrap: {:muontrap, "~> 2.0", optional: true},
  net_runner: {:net_runner, "~> 1.6", optional: true}
}

defp optional_deps("no_native"), do: []
defp optional_deps("muontrap"), do: [@optional_deps.muontrap]
defp optional_deps("net_runner"), do: [@optional_deps.net_runner]
# No blend, and any consumer evaluating this file from deps/bibbidi: everything.
defp optional_deps(_), do: Map.values(@optional_deps)

defp active_blend do
  if File.exists?("blend.exs"), do: System.get_env("BLEND"), else: nil
end
```

Plus `.gitignore` entries `/blend/*/_build` and `/blend/*/deps` (the `blend/*/mix.lock`
files and `blend/premix.exs` are committed, as in waffle_gcs).

### `packages/bibbidi/test/test_helper.exs` delta

See §4: compute `missing_adapter_tags` with `Code.ensure_loaded?/1` and pass
`exclude: [:integration | missing_adapter_tags]` to `ExUnit.start/1`. Adapter integration
test modules additionally carry the conditional `@moduletag skip:` from §5.

### Exact local commands

One-time setup, from `packages/bibbidi/`:

```sh
mix deps.get                 # pulls blend into the main deps/
mix blend.install            # writes blend.exs; replace with the sketch above
mix blend.gen.premix         # writes blend/premix.exs
# add the mix.exs delta and the .gitignore lines

# per-blend lockfiles seeded from the main lock (versions identical, absent deps dropped)
for b in $(mix blend.list); do
  mkdir -p blend/$b && cp mix.lock blend/$b/mix.lock
  BLEND=$b mix deps.get
  BLEND=$b mix deps.unlock --unused
done
```

Running the whole matrix (unit + Firefox integration), from `packages/bibbidi/`:

```sh
mix test.all                            # main lock: every optional dep present
BLEND=no_native  mix test.all
BLEND=muontrap   mix test.all
BLEND=net_runner mix test.all
```

or, as one loop that stops on the first red blend:

```sh
mix test.all && for b in $(mix blend.list); do BLEND=$b mix test.all || break; done
```

Candidate alias for `mix.exs` once this lands (so `CLAUDE.md` can say "run
`mix test.matrix` before finishing"): a tiny Mix task or shell script that runs the
above; a plain `aliases:` entry cannot set env vars per step.

Housekeeping:

```sh
mix blend.list                          # the three names
BLEND=muontrap mix deps.get             # after a mix.exs dep change, per blend
mix blend.clean                         # `mix clean --deps` in every blend + drop stale lockfiles
BBD_DEBUG=1 BLEND=net_runner mix test.all   # headed Firefox under a blend
```

## Gotchas

1. **blend never removes a dep.** Overrides are `List.keystore/4` merges used only for
   lockfile resolution; the run-time deps list is `mix.exs`'s. Absence must be modelled in
   `mix.exs`. (§3)
2. **Pins outside the `mix.exs` requirement fail at run time** with "does not match the
   requirement". Irrelevant to this matrix but worth knowing when a version blend is added
   later. (§3)
3. **`--include integration` beats every `exclude`.** Adapter integration tests need the
   module-level `@moduletag skip:` guard. (§5)
4. **`mix blend.get` under a blend-dependent deps list** writes every optional dep into
   every lockfile (host deps are evaluated with `BLEND` unset) and re-adds them after
   `deps.unlock --unused`. Use the seeded `BLEND=x mix deps.get` recipe, or accept inert
   entries and never run `--check-unused` under a blend. (§3)
5. **Consumers see your `BLEND`.** A dep's `mix.exs` is evaluated with the consumer's env.
   Guard on `File.exists?("blend.exs")` and fall back to the full dep list for unknown
   names. Verified. (§3)
6. **`BLEND=typo` raises `KeyError`** from `premix.exs` (`Map.fetch!`), before any task runs.
7. **`BLEND` is not a `BBD_*` variable.** `CLAUDE.md` says all project env vars use the
   `BBD_` prefix; `BLEND` is blend's own, hardcoded in the generated `premix.exs`
   (regenerated by `mix blend.gen.premix`). Either document the exception in `CLAUDE.md`
   or hand-maintain `premix.exs` with a `BBD_BLEND` alias. Owner's call.
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
    Mix resolves it fine today (Mix.Project.deps_path/0 returned the absolute path).
    Noted in case a future Mix tightens this.

## What this leaves for the next tickets

- Whether adapter modules in `lib/` compile conditionally on the dep (then the test
  guard can target the adapter module) or always compile with `@compile {:no_warn_undefined, ...}`.
- Whether to add a `mix test.matrix` task/script, and the `BLEND` vs `BBD_BLEND` naming
  (gotcha 7).
- The GitHub Actions workflow itself (§6), after the local matrix exists.
