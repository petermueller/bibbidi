defmodule Bibbidi.Commands.Session do
  @moduledoc """
  Command builders for the `session` module of the WebDriver BiDi protocol.

  For convenience, see also `Bibbidi.Session` which wraps these with a
  higher-level API.
  """

  alias Bibbidi.Connection

  @doc """
  Creates a new session.
  """
  @spec new(GenServer.server(), map()) :: {:ok, map()} | {:error, term()}
  def new(conn, capabilities \\ %{}) do
    Connection.send_command(conn, "session.new", %{capabilities: capabilities})
  end

  @doc """
  Ends the current session.
  """
  @spec end_session(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def end_session(conn) do
    Connection.send_command(conn, "session.end", %{})
  end

  @doc """
  Gets the status of the remote end.
  """
  @spec status(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def status(conn) do
    Connection.send_command(conn, "session.status", %{})
  end

  @doc """
  Subscribes to events on the server side.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the subscription.
  """
  @spec subscribe(GenServer.server(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def subscribe(conn, events, opts \\ []) do
    params = %{events: events}
    params = put_opt(params, :contexts, opts)
    Connection.send_command(conn, "session.subscribe", params)
  end

  @doc """
  Unsubscribes from events on the server side.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the unsubscription.
  """
  @spec unsubscribe(GenServer.server(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def unsubscribe(conn, events, opts \\ []) do
    params = %{events: events}
    params = put_opt(params, :contexts, opts)
    Connection.send_command(conn, "session.unsubscribe", params)
  end

  defp put_opt(params, key, opts) do
    case Keyword.get(opts, key) do
      nil -> params
      value -> Map.put(params, key, value)
    end
  end
end
