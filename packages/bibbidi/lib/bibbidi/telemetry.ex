defmodule Bibbidi.Telemetry do
  @moduledoc """
  Telemetry events emitted by Bibbidi.

  ## Command Lifecycle

  Emitted by `Bibbidi.Connection.execute/3`:

  ### `[:bibbidi, :command, :start]`

  Emitted when a command is about to be sent.

  **Measurements:** `%{system_time: integer()}`

  **Metadata:**
  - `:command` — the `Encodable` struct being sent
  - `:method` — the BiDi method string (e.g., `"browsingContext.navigate"`)
  - `:params` — the encoded params map
  - `:connection` — the connection pid or name
  - `:meta` — user-supplied correlation data from the command struct (nil if not set)

  ### `[:bibbidi, :command, :stop]`

  Emitted when a response is received (success or error).

  **Measurements:** `%{duration: integer()}` (native time units)

  **Metadata:** same as `:start`, plus:
  - `:result` — `{:ok, response}` or `{:error, reason}`

  ### `[:bibbidi, :command, :exception]`

  Emitted when the send/receive raises an exception.

  **Measurements:** `%{duration: integer()}`

  **Metadata:** same as `:start`, plus:
  - `:kind` — `:throw`, `:error`, or `:exit`
  - `:reason` — the exception or thrown value
  - `:stacktrace` — the stacktrace

  ## BiDi Events

  Emitted by `Bibbidi.Connection` when a BiDi event is received
  from the browser (navigation events, console messages, network
  activity, etc.):

  ### `[:bibbidi, :event, :received]`

  **Measurements:** `%{system_time: integer()}`

  **Metadata:**
  - `:event` — the BiDi event name (e.g., `"browsingContext.load"`)
  - `:params` — parsed event struct (or raw map for unknown events)
  - `:connection` — the connection pid
  - `:context` — browsing context ID (when present in the event)
  - `:navigation` — navigation ID (when present in the event)
  - `:request` — request data (when present in the event)

  ## Correlation

  Command structs carry an optional `:meta` field for user-supplied correlation
  data. This is included in command telemetry metadata but excluded from the
  wire params. Event structs derive correlation keys (`:context`, `:navigation`,
  `:request`) automatically via `Bibbidi.Telemetry.Metadata`.

  This enables correlating commands with the events they trigger:

      # Tag a navigation command
      cmd = %BrowsingContext.Navigate{url: "https://example.com", context: ctx, meta: %{trace_id: id}}

      # The :start/:stop telemetry will include meta: %{trace_id: id}
      # The browsingContext.load event telemetry will include context: ctx, navigation: nav_id
  """
end
