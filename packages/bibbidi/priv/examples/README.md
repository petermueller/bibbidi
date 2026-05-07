# Generator example registry

`mix bibbidi.gen` looks up usage examples in this directory when it emits
a generated `@moduledoc` or `@doc`. Drop a markdown file here, regenerate,
and the contents land in the rendered docs without touching the generator.

## Naming

One file per emission point, named after the **fully-qualified Elixir name**
(no arity suffix on functions). The four emission points and their key
shapes:

| Generator output | Example file |
| --- | --- |
| Command struct module `@moduledoc` | `Bibbidi.Commands.<Module>.<Command>.md` |
| Facade builder function `@doc` | `Bibbidi.Commands.<Module>.<function>.md` |
| Event struct module `@moduledoc` | `Bibbidi.Events.<Module>.<Struct>.md` |
| Event helper function `@doc` | `Bibbidi.Events.<Module>.<function>.md` |

`<Module>` follows the codegen's CamelCase form (e.g. `Session`,
`BrowsingContext`, `Network`). `<function>` is the snake_case facade
builder name (matches the BiDi command's last segment, e.g. `subscribe`,
`navigate`, `add_intercept`).

Concrete examples:

- `Bibbidi.Commands.Session.Subscribe.md` — splices into the moduledoc of
  `Bibbidi.Commands.Session.Subscribe` (the command struct).
- `Bibbidi.Commands.Session.subscribe.md` — splices into the @doc of
  `Bibbidi.Commands.Session.subscribe/2` (the facade builder).
- `Bibbidi.Events.BrowsingContext.ContextCreated.md` — splices into the
  moduledoc of the event struct.
- `Bibbidi.Events.BrowsingContext.context_created.md` — splices into the
  @doc of the helper that returns the BiDi method name.

Files for emission points that don't exist (typo, wrong case, etc.) are
silently ignored — the generator just emits today's docstring. Missing
files are normal and intentional: examples are added incrementally.

## What goes in the file

Plain markdown. The generator wraps whatever you write in a
`## Examples` section, so don't add that heading yourself. Code fences,
links, and inline formatting all work as expected.

```markdown
Subscribe to log entries on every browsing context:

​```elixir
{:ok, _} =
  Bibbidi.Commands.Session.subscribe(conn, ["log.entryAdded"])
​```

The connection then receives `{:bibbidi_event, "log.entryAdded", params}`
messages for each emitted entry.
```

After `mix bibbidi.gen`, the rendered `@doc` will contain:

```
## Examples

Subscribe to log entries on every browsing context:

    {:ok, _} =
      Bibbidi.Commands.Session.subscribe(conn, ["log.entryAdded"])

The connection then receives `{:bibbidi_event, "log.entryAdded", params}`
messages for each emitted entry.
```

## Why this directory

These files ship inside the package's `priv/` so they're always available
at codegen time. They are **not** evaluated at runtime — the generator
reads them while emitting source under `lib/bibbidi/{commands,events}/`,
and the rendered example becomes a literal part of the generated module's
docstring.
