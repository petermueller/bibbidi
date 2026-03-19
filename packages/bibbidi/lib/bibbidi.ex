defmodule Bibbidi do
  @moduledoc """
  WebDriver BiDi Protocol implementation for Elixir.

  Bibbidi is a low-level building block library for the W3C WebDriver BiDi
  protocol. It provides WebSocket connectivity, command/response correlation,
  and event dispatch — but imposes no supervision tree. Users are expected
  to supervise `Bibbidi.Connection` processes themselves.

  ## Quick Start

      # Connect to a BiDi endpoint
      {:ok, conn} = Bibbidi.Connection.start_link(url: "ws://localhost:9222/session")

      # Send commands
      {:ok, result} = Bibbidi.Commands.BrowsingContext.get_tree(conn)

      # Subscribe to events
      Bibbidi.Connection.subscribe(conn, "browsingContext.load")
      receive do
        {:bibbidi_event, "browsingContext.load", params} -> params
      end

  ## Modules

  - `Bibbidi.Connection` — Core GenServer managing WebSocket + command correlation
  - `Bibbidi.Session` — Session lifecycle (new, end, status, subscribe)
  - `Bibbidi.Commands.BrowsingContext` — Browsing context commands
  - `Bibbidi.Commands.Script` — Script evaluation commands
  - `Bibbidi.Commands.Session` — Session commands
  - `Bibbidi.Protocol` — Pure JSON encode/decode
  - `Bibbidi.Transport` — Swappable transport behaviour
  - `Bibbidi.Transport.MintWS` — Default Mint.WebSocket transport
  """
end
