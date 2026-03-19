defmodule Bibbidi.Session do
  @moduledoc """
  Session lifecycle management for WebDriver BiDi.

  This is a functional module — all functions take a connection pid.
  Users control their own supervision.

  ## Usage

      {:ok, conn} = Bibbidi.Connection.start_link(url: bidi_url)
      {:ok, capabilities} = Bibbidi.Session.new(conn)

      # ... do work ...

      :ok = Bibbidi.Session.end_session(conn)
  """

  alias Bibbidi.Connection

  @doc """
  Connects to a BiDi endpoint and creates a new session in one step.

  Accepts the same options as `Bibbidi.Connection.start_link/1` plus:

    * `:capabilities` — capabilities map to send with `session.new` (default: `%{}`)

  Returns `{:ok, conn, capabilities}` on success.

  ## Example

      {:ok, conn, capabilities} = Bibbidi.Session.start(url: bidi_url)
  """
  @spec start(keyword()) :: {:ok, pid(), map()} | {:error, term()}
  def start(opts) do
    {capabilities, conn_opts} = Keyword.pop(opts, :capabilities, %{})

    with {:ok, conn} <- Connection.start_link(conn_opts),
         {:ok, caps} <- new(conn, capabilities) do
      {:ok, conn, caps}
    end
  end

  @doc """
  Creates a new BiDi session.

  Returns `{:ok, capabilities}` on success.
  """
  @spec new(GenServer.server(), map()) :: {:ok, map()} | {:error, term()}
  def new(conn, capabilities \\ %{}) do
    Bibbidi.Commands.Session.new(conn, capabilities)
  end

  @doc """
  Ends the current BiDi session.
  """
  @spec end_session(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def end_session(conn) do
    Bibbidi.Commands.Session.session_end(conn)
  end

  @doc """
  Gets the status of the BiDi server.
  """
  @spec status(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def status(conn) do
    Bibbidi.Commands.Session.status(conn)
  end

  @doc """
  Subscribes to BiDi events on the server side.

  This tells the server to start sending these events. Use
  `Bibbidi.Connection.subscribe/3` to receive them in your process.
  """
  @spec subscribe(GenServer.server(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def subscribe(conn, events, opts \\ []) do
    Bibbidi.Commands.Session.subscribe(conn, events, opts)
  end

  @doc """
  Unsubscribes from BiDi events on the server side.

  ## Options

  - `:subscriptions` - List of subscription IDs to unsubscribe (alternative to events).
  """
  @spec unsubscribe(GenServer.server(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def unsubscribe(conn, events, opts \\ []) do
    unsub_opts = [events: events]

    unsub_opts =
      if opts[:subscriptions],
        do: [{:subscriptions, opts[:subscriptions]} | unsub_opts],
        else: unsub_opts

    Bibbidi.Commands.Session.unsubscribe(conn, unsub_opts)
  end
end
