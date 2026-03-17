defmodule Bibbidi.Commands.Input do
  @moduledoc """
  Command builders for the `input` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Performs a sequence of input actions in a browsing context.

  `actions` is a list of source action maps, each describing a sequence of
  key, pointer, wheel, or pause actions.
  """
  @spec perform_actions(GenServer.server(), String.t(), [map()]) ::
          {:ok, map()} | {:error, term()}
  def perform_actions(conn, context, actions) do
    Connection.execute(conn, %__MODULE__.PerformActions{context: context, actions: actions})
  end

  @doc """
  Releases all keys and pointer buttons in a browsing context.
  """
  @spec release_actions(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def release_actions(conn, context) do
    Connection.execute(conn, %__MODULE__.ReleaseActions{context: context})
  end

  @doc """
  Sets the files for a file input element.

  `element` is a shared reference map identifying the file input element.
  `files` is a list of file path strings.
  """
  @spec set_files(GenServer.server(), String.t(), map(), [String.t()]) ::
          {:ok, map()} | {:error, term()}
  def set_files(conn, context, element, files) do
    Connection.execute(conn, %__MODULE__.SetFiles{
      context: context,
      element: element,
      files: files
    })
  end
end
