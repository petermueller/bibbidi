# Bibbidi

<img src="assets/icon.png" alt="Bibbidi icon" width="120" align="right" />

Low-level Elixir implementation of the [W3C WebDriver BiDi Protocol](https://w3c.github.io/webdriver-bidi/).

Bibbidi is a **building-block library** — it gives you WebSocket connectivity,
command/response correlation, and event dispatch, but imposes no supervision
tree. You supervise `Bibbidi.Connection` processes yourself, exactly how you
want.

Designed for RPA frameworks, browser testing libraries, and anything else that
needs to talk BiDi to a browser.

## Installation

```elixir
def deps do
  [
    {:bibbidi, "~> 0.1.0"}
  ]
end
```

## Quick Start

Launch a browser with BiDi support (Firefox has native support):

```bash
firefox --headless --remote-debugging-port=9222
```

Then in IEx:

```elixir
# Connect to the BiDi WebSocket endpoint
{:ok, conn} = Bibbidi.Connection.start_link(url: "ws://localhost:9222/session")

# Check server status
{:ok, status} = Bibbidi.Session.status(conn)
IO.inspect(status)
# => %{"ready" => true, "message" => ""}

# Start a session
{:ok, caps} = Bibbidi.Session.new(conn)

# Get the browsing context tree
{:ok, tree} = Bibbidi.Commands.BrowsingContext.get_tree(conn)
context = hd(tree["contexts"])["context"]

# Navigate to a page
{:ok, nav} = Bibbidi.Commands.BrowsingContext.navigate(conn, context, "https://example.com", wait: "complete")

# Evaluate JavaScript
{:ok, result} = Bibbidi.Commands.Script.evaluate(conn, "document.title", %{context: context})
IO.inspect(result)
# => %{"type" => "success", "result" => %{"type" => "string", "value" => "Example Domain"}, ...}

# Call a function with arguments
{:ok, result} = Bibbidi.Commands.Script.call_function(
  conn,
  "function(a, b) { return a + b; }",
  %{context: context},
  arguments: [%{type: "number", value: 3}, %{type: "number", value: 4}]
)

# Take a screenshot (returns base64-encoded PNG)
{:ok, screenshot} = Bibbidi.Commands.BrowsingContext.capture_screenshot(conn, context)
File.write!("screenshot.png", Base.decode64!(screenshot["data"]))

# End the session
{:ok, _} = Bibbidi.Session.end_session(conn)
Bibbidi.Connection.close(conn)
```

## Example Module

A copy-pasteable module showing common patterns:

```elixir
defmodule MyApp.Browser do
  alias Bibbidi.{Connection, Session}
  alias Bibbidi.Commands.{BrowsingContext, Script}

  def run do
    {:ok, conn} = Connection.start_link(url: "ws://localhost:9222/session")
    {:ok, _caps} = Session.new(conn)

    try do
      {:ok, tree} = BrowsingContext.get_tree(conn)
      context = hd(tree["contexts"])["context"]

      # Navigate and wait for full page load
      {:ok, _} = BrowsingContext.navigate(conn, context, "https://example.com", wait: "complete")

      # Extract page title
      {:ok, %{"result" => %{"value" => title}}} =
        Script.evaluate(conn, "document.title", %{context: context})

      # Extract all links
      {:ok, %{"result" => %{"value" => links}}} =
        Script.evaluate(
          conn,
          ~s|Array.from(document.querySelectorAll("a"), a => a.href)|,
          %{context: context}
        )

      %{title: title, links: links}
    after
      Session.end_session(conn)
      Connection.close(conn)
    end
  end
end
```

## Listening for Events

```elixir
{:ok, conn} = Bibbidi.Connection.start_link(url: "ws://localhost:9222/session")
{:ok, _} = Bibbidi.Session.new(conn)

# Tell the server to send browsingContext events
{:ok, _} = Bibbidi.Session.subscribe(conn, ["browsingContext.load"])

# Tell the connection to forward them to us
:ok = Bibbidi.Connection.subscribe(conn, "browsingContext.load")

{:ok, tree} = Bibbidi.Commands.BrowsingContext.get_tree(conn)
context = hd(tree["contexts"])["context"]

# Navigate — this will trigger a load event
{:ok, _} = Bibbidi.Commands.BrowsingContext.navigate(conn, context, "https://example.com")

# Receive the event
receive do
  {:bibbidi_event, "browsingContext.load", params} ->
    IO.puts("Page loaded: #{params["url"]}")
after
  10_000 -> IO.puts("Timeout waiting for load event")
end
```

## Supervision

Bibbidi doesn't impose a process tree. Add connections to your own supervisor:

```elixir
children = [
  {Bibbidi.Connection, url: "ws://localhost:9222/session", name: MyApp.Browser}
]

Supervisor.start_link(children, strategy: :one_for_one)

# Then use the named process
Bibbidi.Commands.BrowsingContext.get_tree(MyApp.Browser)
```

## Available Command Modules

| Module                             | Commands                                                                                                                                  |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `Bibbidi.Commands.BrowsingContext` | navigate, getTree, create, close, captureScreenshot, print, reload, setViewport, handleUserPrompt, activate, traverseHistory, locateNodes |
| `Bibbidi.Commands.Script`          | evaluate, callFunction, getRealms, disown, addPreloadScript, removePreloadScript                                                          |
| `Bibbidi.Commands.Session`         | new, end, status, subscribe, unsubscribe                                                                                                  |
| `Bibbidi.Session`                  | Higher-level session lifecycle (new, end_session, status, subscribe, unsubscribe)                                                         |

## Architecture

- **`Bibbidi.Connection`** — GenServer owning the WebSocket. Correlates command IDs to callers, dispatches events to subscribers.
- **`Bibbidi.Protocol`** — Pure JSON encode/decode, no process state.
- **`Bibbidi.Transport`** — Behaviour for swappable WebSocket transports.
- **`Bibbidi.Transport.MintWS`** — Default transport using [mint_web_socket](https://hex.pm/packages/mint_web_socket).
