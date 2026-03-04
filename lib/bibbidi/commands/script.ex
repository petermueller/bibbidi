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
    params = %{
      expression: expression,
      target: target,
      awaitPromise: Keyword.get(opts, :await_promise, true)
    }

    params = put_opt(params, :result_ownership, opts, :resultOwnership)
    params = put_opt(params, :serialization_options, opts, :serializationOptions)
    params = put_opt(params, :user_activation, opts, :userActivation)
    Connection.send_command(conn, "script.evaluate", params)
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
    params = %{
      functionDeclaration: function_declaration,
      target: target,
      awaitPromise: Keyword.get(opts, :await_promise, true)
    }

    params = put_opt(params, :arguments, opts)
    params = put_opt(params, :this, opts)
    params = put_opt(params, :result_ownership, opts, :resultOwnership)
    params = put_opt(params, :serialization_options, opts, :serializationOptions)
    params = put_opt(params, :user_activation, opts, :userActivation)
    Connection.send_command(conn, "script.callFunction", params)
  end

  @doc """
  Gets the realms associated with a browsing context.

  ## Options

  - `:context` - Filter by browsing context ID.
  - `:type` - Filter by realm type.
  """
  @spec get_realms(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_realms(conn, opts \\ []) do
    params = %{}
    params = put_opt(params, :context, opts)
    params = put_opt(params, :type, opts)
    Connection.send_command(conn, "script.getRealms", params)
  end

  @doc """
  Disowns the given script handles, allowing them to be garbage collected.
  """
  @spec disown(GenServer.server(), [String.t()], map()) :: {:ok, map()} | {:error, term()}
  def disown(conn, handles, target) do
    Connection.send_command(conn, "script.disown", %{handles: handles, target: target})
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
    params = %{functionDeclaration: function_declaration}
    params = put_opt(params, :contexts, opts)
    params = put_opt(params, :sandbox, opts)
    Connection.send_command(conn, "script.addPreloadScript", params)
  end

  @doc """
  Removes a previously added preload script.
  """
  @spec remove_preload_script(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def remove_preload_script(conn, script_id) do
    Connection.send_command(conn, "script.removePreloadScript", %{script: script_id})
  end

  ## Private

  defp put_opt(params, key, opts, json_key \\ nil) do
    json_key = json_key || key

    case Keyword.get(opts, key) do
      nil -> params
      value -> Map.put(params, json_key, value)
    end
  end
end
