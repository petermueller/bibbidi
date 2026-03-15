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
    Connection.execute(conn, %__MODULE__.New{capabilities: capabilities})
  end

  @doc """
  Ends the current session.
  """
  @spec end_session(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def end_session(conn) do
    Connection.execute(conn, %__MODULE__.End{})
  end

  @doc """
  Gets the status of the remote end.
  """
  @spec status(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def status(conn) do
    Connection.execute(conn, %__MODULE__.Status{})
  end

  @doc """
  Subscribes to events on the server side.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the subscription.
  """
  @spec subscribe(GenServer.server(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def subscribe(conn, events, opts \\ []) do
    Connection.execute(conn, %__MODULE__.Subscribe{
      events: events,
      contexts: opts[:contexts]
    })
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

    params =
      case opts[:contexts] do
        nil -> params
        contexts -> Map.put(params, :contexts, contexts)
      end

    Connection.send_command(conn, "session.unsubscribe", params)
  end
end
