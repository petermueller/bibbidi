defmodule Bibbidi.Commands.Browser do
  @moduledoc """
  Command builders for the `browser` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Closes the browser.
  """
  @spec close(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def close(conn) do
    Connection.execute(conn, %__MODULE__.Close{})
  end

  @doc """
  Creates a new user context (profile).

  ## Options

  - `:accept_insecure_certs` - Whether to accept insecure TLS certificates.
  - `:proxy` - Proxy configuration map.
  - `:unhandled_prompt_behavior` - How to handle unhandled prompts.
  """
  @spec create_user_context(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_user_context(conn, opts \\ []) do
    Connection.execute(conn, %__MODULE__.CreateUserContext{
      accept_insecure_certs: opts[:accept_insecure_certs],
      proxy: opts[:proxy],
      unhandled_prompt_behavior: opts[:unhandled_prompt_behavior]
    })
  end

  @doc """
  Gets the list of client windows.
  """
  @spec get_client_windows(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_client_windows(conn) do
    Connection.execute(conn, %__MODULE__.GetClientWindows{})
  end

  @doc """
  Gets the list of user contexts.
  """
  @spec get_user_contexts(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_user_contexts(conn) do
    Connection.execute(conn, %__MODULE__.GetUserContexts{})
  end

  @doc """
  Removes a user context.
  """
  @spec remove_user_context(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def remove_user_context(conn, user_context) do
    Connection.execute(conn, %__MODULE__.RemoveUserContext{user_context: user_context})
  end

  @doc """
  Sets the state of a client window.

  `state_params` is a map that must include `:state` (one of `"fullscreen"`, `"maximized"`,
  `"minimized"`, `"normal"`). When `state` is `"normal"`, it may also include `:width`,
  `:height`, `:x`, and `:y`.
  """
  @spec set_client_window_state(GenServer.server(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def set_client_window_state(conn, client_window, state_params) do
    params = Map.put(state_params, :clientWindow, client_window)
    Connection.send_command(conn, "browser.setClientWindowState", params)
  end

  @doc """
  Sets the download behavior for the browser.

  `download_behavior` is a map describing the behavior (e.g.
  `%{type: "allowed", destinationFolder: "/tmp"}` or `%{type: "denied"}`),
  or `nil` to reset to default.

  ## Options

  - `:user_contexts` - List of user context IDs to scope the behavior to.
  """
  @spec set_download_behavior(GenServer.server(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_download_behavior(conn, download_behavior, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetDownloadBehavior{
      download_behavior: download_behavior,
      user_contexts: opts[:user_contexts]
    })
  end
end
