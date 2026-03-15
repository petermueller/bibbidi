defmodule Bibbidi.Commands.WebExtension do
  @moduledoc """
  Command builders for the `webExtension` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Installs a web extension.

  `extension_data` is a map describing the extension source. One of:

  - `%{type: "path", path: "/path/to/extension"}`
  - `%{type: "archivePath", path: "/path/to/extension.zip"}`
  - `%{type: "base64", value: "base64-encoded-data"}`
  """
  @spec install(GenServer.server(), map()) :: {:ok, map()} | {:error, term()}
  def install(conn, extension_data) do
    Connection.execute(conn, %__MODULE__.Install{extension_data: extension_data})
  end

  @doc """
  Uninstalls a web extension.
  """
  @spec uninstall(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def uninstall(conn, extension) do
    Connection.execute(conn, %__MODULE__.Uninstall{extension: extension})
  end
end
