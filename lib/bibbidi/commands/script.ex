defmodule Bibbidi.Commands.Script do
  @moduledoc """
  Command builders for the `script` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Evaluates a JavaScript expression in the given target.

  `target` is a map like `%{context: "ctx-id"}` or `%{realm: "realm-id"}`.

  ## Options

  - `:await_promise` - Whether to await the result if it's a Promise. Defaults to `true`.
  - `:result_ownership` - `"root"` or `"none"`. Defaults to `"none"`.
  - `:serialization_options` - Serialization options map.
  - `:user_activation` - Whether to simulate user activation.
  """
  @spec evaluate(GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def evaluate(conn, expression, target, opts \\ []) do
    Connection.execute(conn, %__MODULE__.Evaluate{
      expression: expression,
      target: target,
      await_promise: Keyword.get(opts, :await_promise, true),
      result_ownership: opts[:result_ownership],
      serialization_options: opts[:serialization_options],
      user_activation: opts[:user_activation]
    })
  end

  @doc """
  Calls a function in the given target.

  ## Options

  - `:arguments` - List of argument values.
  - `:await_promise` - Whether to await the result if it's a Promise. Defaults to `true`.
  - `:this` - The `this` value for the function call.
  - `:result_ownership` - `"root"` or `"none"`.
  - `:serialization_options` - Serialization options map.
  - `:user_activation` - Whether to simulate user activation.
  """
  @spec call_function(GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def call_function(conn, function_declaration, target, opts \\ []) do
    Connection.execute(conn, %__MODULE__.CallFunction{
      function_declaration: function_declaration,
      target: target,
      await_promise: Keyword.get(opts, :await_promise, true),
      arguments: opts[:arguments],
      this: opts[:this],
      result_ownership: opts[:result_ownership],
      serialization_options: opts[:serialization_options],
      user_activation: opts[:user_activation]
    })
  end

  @doc """
  Gets the realms associated with a browsing context.

  ## Options

  - `:context` - Filter by browsing context ID.
  - `:type` - Filter by realm type.
  """
  @spec get_realms(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_realms(conn, opts \\ []) do
    Connection.execute(conn, %__MODULE__.GetRealms{
      context: opts[:context],
      type: opts[:type]
    })
  end

  @doc """
  Disowns the given script handles, allowing them to be garbage collected.
  """
  @spec disown(GenServer.server(), [String.t()], map()) :: {:ok, map()} | {:error, term()}
  def disown(conn, handles, target) do
    Connection.execute(conn, %__MODULE__.Disown{handles: handles, target: target})
  end

  @doc """
  Adds a preload script that runs before any page script.

  ## Options

  - `:contexts` - List of browsing context IDs to limit the script to.
  - `:sandbox` - Sandbox name.
  """
  @spec add_preload_script(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_preload_script(conn, function_declaration, opts \\ []) do
    Connection.execute(conn, %__MODULE__.AddPreloadScript{
      function_declaration: function_declaration,
      contexts: opts[:contexts],
      sandbox: opts[:sandbox]
    })
  end

  @doc """
  Removes a previously added preload script.
  """
  @spec remove_preload_script(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def remove_preload_script(conn, script_id) do
    Connection.execute(conn, %__MODULE__.RemovePreloadScript{script: script_id})
  end
end
