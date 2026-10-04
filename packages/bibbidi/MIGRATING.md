# MIGRATING

## 0.3.x → 0.4.0

### Subscriber message shape

`{:bibbidi_event, method, params}` is gone. The shape is now configurable
via `t:Bibbidi.Connection.wrap_spec/0` (per-subscribe `:wrap` opt or
`:default_event_wrapper` app env). Default is identity — subscribers get
the parsed struct directly.

**To update to 0.4 patterns** — pattern-match on the struct, or use
`Bibbidi.Events.Guards`:

```elixir
import Bibbidi.Events.Guards

def handle_info(%Bibbidi.Events.BrowsingContext.Load{} = ev, state), do: ...
def handle_info(msg, state) when is_bibbidi_log_event(msg), do: ...
def handle_info(msg, state) when is_bibbidi_event(msg), do: ...
```

Events outside the codegen arrive as `t:Bibbidi.Events.Unknown.t/0`.

**To stay on the pre-0.4 tuple shape** — ship a helper and point
`:default_event_wrapper` at it (MFA-only; config can't carry function
captures):

```elixir
defmodule MyApp.BibbidiLegacy do
  def wrap(event), do: {:bibbidi_event, Bibbidi.Events.method_for(event), event}
end

config :bibbidi, default_event_wrapper: {MyApp.BibbidiLegacy, :wrap, []}
```

Or per-subscribe with a function literal — see `Bibbidi.Connection.subscribe/4`.
Third element is now a struct rather than a raw map; unwrap in your helper
if you need full 0.3 parity (see `Bibbidi.Events.method_for/1`).

### Type module renames

Generated aliases picked up canonical acronym casing:

| 0.3                                                 | 0.4                                                 |
| --------------------------------------------------- | --------------------------------------------------- |
| `Bibbidi.Types.Network.Base64value`                 | `Bibbidi.Types.Network.Base64Value`                 |
| `Bibbidi.Types.BrowsingContext.XpathLocator`        | `Bibbidi.Types.BrowsingContext.XPathLocator`        |
| `Bibbidi.Types.Script.HtmlcollectionRemoteValue`    | `Bibbidi.Types.Script.HTMLCollectionRemoteValue`    |
| `Bibbidi.Types.WebExtension.ExtensionBase64encoded` | `Bibbidi.Types.WebExtension.ExtensionBase64Encoded` |

### `Bibbidi.Events.parse/2`

Now total — returns `t:Bibbidi.Events.Unknown.t/0` for events outside
the codegen instead of falling through to the raw params map.
