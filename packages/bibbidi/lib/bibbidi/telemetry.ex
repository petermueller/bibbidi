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
  - `:params` — the event params map from the browser
  - `:connection` — the connection pid
  """
end
