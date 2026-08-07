# Generator example registry

`mix bibbidi.gen` looks up usage examples in this directory when it emits a
generated `@moduledoc` or `@doc`. Drop a markdown file here, regenerate, and the
contents land in the rendered docs without touching the generator.

This is the "Examples" section of the documentation registry
(`Bibbidi.CDDL.Generator.Docs`). Examples is the only section today; the registry
is built to take more (see "Adding a section" below).

## Naming

One file per emission point, named after the **fully-qualified Elixir name** (no
arity suffix on functions). `@moduledoc` examples go under `module/` and `@doc`
examples under `function/` — the split keeps a struct moduledoc and its facade's
`@doc` from clobbering each other on case-insensitive filesystems (where
`Subscribe.md` and `subscribe.md` are the same file).

| Generator output | Example file |
| --- | --- |
| Command struct module `@moduledoc` | `module/Bibbidi.Commands.<Module>.<Command>.md` |
| Facade builder function `@doc` | `function/Bibbidi.Commands.<Module>.<function>.md` |
| Event struct module `@moduledoc` | `module/Bibbidi.Events.<Module>.<Struct>.md` |
| Event helper function `@doc` | `function/Bibbidi.Events.<Module>.<function>.md` |

`<Module>` follows the codegen's CamelCase form (e.g. `Session`,
`BrowsingContext`, `Network`). `<function>` is the snake_case facade builder name
(matches the BiDi command's last segment, e.g. `subscribe`, `navigate`,
`add_preload_script`).

Concrete examples:

- `module/Bibbidi.Commands.Session.Subscribe.md` — splices into the moduledoc of
  `Bibbidi.Commands.Session.Subscribe` (the command struct).
- `function/Bibbidi.Commands.Session.subscribe.md` — splices into the @doc of
  `Bibbidi.Commands.Session.subscribe/2` (the facade builder).
- `module/Bibbidi.Events.BrowsingContext.ContextCreated.md` — splices into the
  moduledoc of the event struct.
- `function/Bibbidi.Events.BrowsingContext.context_created.md` — splices into the
  @doc of the helper that returns the BiDi method name.

Files for emission points that don't exist (typo, wrong case, wrong subfolder,
etc.) are silently ignored — the generator just emits today's docstring. Missing
files are normal and intentional: examples are added incrementally.

## What goes in the file

Plain markdown. The generator wraps whatever you write in a `## Examples`
section, so don't add that heading yourself. Code fences, links, and inline
formatting all work as expected.

```markdown
Subscribe to log entries on every browsing context:

​```elixir
{:ok, _} = Bibbidi.Commands.Session.subscribe(conn, ["log.entryAdded"])
​```

The subscribed pid then receives `%Bibbidi.Events.Log.EntryAdded{}` structs
for each emitted entry (see `Bibbidi.Events.Guards` for category guards).
```

After `mix bibbidi.gen`, the rendered `@doc` will contain:

```
## Examples

Subscribe to log entries on every browsing context:

    {:ok, _} = Bibbidi.Commands.Session.subscribe(conn, ["log.entryAdded"])

The subscribed pid then receives `%Bibbidi.Events.Log.EntryAdded{}` structs
for each emitted entry (see `Bibbidi.Events.Guards` for category guards).
```

## Adding a section

The registry is not hard-wired to "Examples". Each section is one entry in
`Bibbidi.CDDL.Generator.Docs.sections/0`:

```elixir
%{key: :examples, heading: "Examples", dir: "priv/examples"}
```

To introduce, say, a "Usage" section, add `%{key: :usage, heading: "Usage", dir:
"priv/usage"}` to that list and create the folder. Files are keyed by the same
fully-qualified Elixir names; the four generator call sites don't change. Each
section's directory can be overridden in tests via `:"<key>_dir"` application env
(the examples section reads `:examples_dir`).

## Why this directory

These files ship inside the package's `priv/` so they're always available at
codegen time. They are **not** evaluated at runtime — the generator reads them
while emitting source under `lib/bibbidi/{commands,events}/`, and the rendered
example becomes a literal part of the generated module's docstring.
