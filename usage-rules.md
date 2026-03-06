# Bibbidi Usage Rules

Low-level Elixir implementation of the W3C WebDriver BiDi Protocol.
Building-block library — no opinionated supervision tree.

## No Auto-Supervision

Bibbidi does NOT provide a supervision tree. You MUST supervise `Bibbidi.Browser` and `Bibbidi.Connection` in your own supervisor:

```elixir
children = [
  {Bibbidi.Browser, [headless: true]},
  {Bibbidi.Connection, [url: "ws://localhost:9222/session"]}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

If Browser or Connection crashes without supervision, the browser process will be orphaned.

## Session Is Functional, Not a Process

`Bibbidi.Session` is a plain module with functions — NOT a GenServer. All its functions take a connection pid:

```elixir
{:ok, result} = Bibbidi.Session.new(conn)
{:ok, result} = Bibbidi.Session.status(conn)
```

`Session.start/1` is a convenience that starts a Connection + calls `session.new`. It returns the connection pid, not a session pid.

## Command Function Signatures

All command functions follow: `(conn, required_args..., opts \\ [])`

- First argument is always the connection pid
- Required BiDi params are positional arguments
- Optional BiDi params are Elixir keyword opts with `snake_case` keys
- Options are automatically mapped to `camelCase` JSON keys
- All commands return `{:ok, map()} | {:error, term()}`

```elixir
# snake_case opts become camelCase in the JSON payload
Bibbidi.Commands.BrowsingContext.navigate(conn, context_id, url, wait: "complete")
Bibbidi.Commands.BrowsingContext.get_tree(conn, max_depth: 2)
```

## Event Subscription Is Two Steps

Receiving events requires both server-side AND client-side subscription:

```elixir
# 1. Tell the browser to START sending events (server-side)
Bibbidi.Session.subscribe(conn, ["browsingContext.load"])

# 2. Register your process to RECEIVE them (client-side)
Bibbidi.Connection.subscribe(conn, "browsingContext.load")

# 3. Events arrive as messages
receive do
  {:bibbidi_event, "browsingContext.load", params} -> params
end
```

Calling only `Connection.subscribe` without `Session.subscribe` first means the browser never sends the events. Calling only `Session.subscribe` without `Connection.subscribe` means events are received by Connection but not forwarded to your process.

## Connection Options

`Bibbidi.Connection.start_link/1` accepts:
- `:url` — WebSocket URL (e.g. `"ws://localhost:9222/session"`)
- `:browser` — A `Bibbidi.Browser` pid (extracts URL automatically)
- `:transport` — Custom transport module (default: `Bibbidi.Transport.MintWS`)
- `:transport_opts` — Options passed to the transport
- `:name` — GenServer name registration

## Common Mistakes

- Treating `Bibbidi.Session` as a process — it's a functional module
- Forgetting server-side `Session.subscribe` before client-side `Connection.subscribe`
- Not supervising Browser/Connection — they are plain GenServers, you must supervise them
- All `Connection.send_command/3` calls are synchronous (`GenServer.call`) with a 30s default timeout
