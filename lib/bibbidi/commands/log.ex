defmodule Bibbidi.Commands.Log do
  @moduledoc """
  Command builders for the `log` module of the WebDriver BiDi protocol.

  The `log` module defines no commands. It only produces events
  (e.g. `log.entryAdded`) which can be subscribed to via
  `Bibbidi.Commands.Session.subscribe/3` and received through
  `Bibbidi.Connection.subscribe/3`.
  """
end
