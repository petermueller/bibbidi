defmodule Bibbidi.Commands.Network do
  @moduledoc """
  Command builders for the `network` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Adds a data collector for network requests.

  ## Options

  - `:collector_type` - The collector type. Defaults to `"blob"`.
  - `:contexts` - List of browsing context IDs to scope the collector.
  - `:user_contexts` - List of user context IDs to scope the collector.
  """
  @spec add_data_collector(GenServer.server(), [String.t()], non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_data_collector(conn, data_types, max_encoded_data_size, opts \\ []) do
    params = %{dataTypes: data_types, maxEncodedDataSize: max_encoded_data_size}
    params = put_opt(params, :collector_type, opts, :collectorType)
    params = put_opt(params, :contexts, opts)
    params = put_opt(params, :user_contexts, opts, :userContexts)
    Connection.send_command(conn, "network.addDataCollector", params)
  end

  @doc """
  Adds a network intercept.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the intercept.
  - `:url_patterns` - List of URL pattern maps to filter intercepted requests.
  """
  @spec add_intercept(GenServer.server(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_intercept(conn, phases, opts \\ []) do
    params = %{phases: phases}
    params = put_opt(params, :contexts, opts)
    params = put_opt(params, :url_patterns, opts, :urlPatterns)
    Connection.send_command(conn, "network.addIntercept", params)
  end

  @doc """
  Continues a request that was intercepted.

  ## Options

  - `:body` - Request body as a bytes value map.
  - `:cookies` - List of cookie header maps.
  - `:headers` - List of header maps.
  - `:method` - HTTP method.
  - `:url` - Request URL.
  """
  @spec continue_request(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def continue_request(conn, request, opts \\ []) do
    params = %{request: request}
    params = put_opt(params, :body, opts)
    params = put_opt(params, :cookies, opts)
    params = put_opt(params, :headers, opts)
    params = put_opt(params, :method, opts)
    params = put_opt(params, :url, opts)
    Connection.send_command(conn, "network.continueRequest", params)
  end

  @doc """
  Continues a response that was intercepted.

  ## Options

  - `:cookies` - List of set-cookie header maps.
  - `:credentials` - Auth credentials map.
  - `:headers` - List of header maps.
  - `:reason_phrase` - HTTP reason phrase.
  - `:status_code` - HTTP status code.
  """
  @spec continue_response(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def continue_response(conn, request, opts \\ []) do
    params = %{request: request}
    params = put_opt(params, :cookies, opts)
    params = put_opt(params, :credentials, opts)
    params = put_opt(params, :headers, opts)
    params = put_opt(params, :reason_phrase, opts, :reasonPhrase)
    params = put_opt(params, :status_code, opts, :statusCode)
    Connection.send_command(conn, "network.continueResponse", params)
  end

  @doc """
  Continues a request that requires authentication.

  `auth_params` is a map containing the authentication action.
  For example, `%{action: "provideCredentials", credentials: %{type: "password", username: "u", password: "p"}}`
  or `%{action: "default"}` or `%{action: "cancel"}`.
  """
  @spec continue_with_auth(GenServer.server(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def continue_with_auth(conn, request, auth_params) do
    params = Map.put(auth_params, :request, request)
    Connection.send_command(conn, "network.continueWithAuth", params)
  end

  @doc """
  Disowns collected data for a request.
  """
  @spec disown_data(GenServer.server(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def disown_data(conn, data_type, collector, request) do
    Connection.send_command(conn, "network.disownData", %{
      dataType: data_type,
      collector: collector,
      request: request
    })
  end

  @doc """
  Fails an intercepted request.
  """
  @spec fail_request(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def fail_request(conn, request) do
    Connection.send_command(conn, "network.failRequest", %{request: request})
  end

  @doc """
  Gets collected data for a request.

  ## Options

  - `:collector` - The collector ID.
  - `:disown` - Whether to disown the data after retrieval. Defaults to `false`.
  """
  @spec get_data(GenServer.server(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_data(conn, data_type, request, opts \\ []) do
    params = %{dataType: data_type, request: request}
    params = put_opt(params, :collector, opts)
    params = put_opt(params, :disown, opts)
    Connection.send_command(conn, "network.getData", params)
  end

  @doc """
  Provides a complete response for an intercepted request.

  ## Options

  - `:body` - Response body as a bytes value map.
  - `:cookies` - List of set-cookie header maps.
  - `:headers` - List of header maps.
  - `:reason_phrase` - HTTP reason phrase.
  - `:status_code` - HTTP status code.
  """
  @spec provide_response(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def provide_response(conn, request, opts \\ []) do
    params = %{request: request}
    params = put_opt(params, :body, opts)
    params = put_opt(params, :cookies, opts)
    params = put_opt(params, :headers, opts)
    params = put_opt(params, :reason_phrase, opts, :reasonPhrase)
    params = put_opt(params, :status_code, opts, :statusCode)
    Connection.send_command(conn, "network.provideResponse", params)
  end

  @doc """
  Removes a data collector.
  """
  @spec remove_data_collector(GenServer.server(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def remove_data_collector(conn, collector) do
    Connection.send_command(conn, "network.removeDataCollector", %{collector: collector})
  end

  @doc """
  Removes a network intercept.
  """
  @spec remove_intercept(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def remove_intercept(conn, intercept) do
    Connection.send_command(conn, "network.removeIntercept", %{intercept: intercept})
  end

  @doc """
  Sets the cache behavior.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the behavior.
  """
  @spec set_cache_behavior(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_cache_behavior(conn, cache_behavior, opts \\ []) do
    params = %{cacheBehavior: cache_behavior}
    params = put_opt(params, :contexts, opts)
    Connection.send_command(conn, "network.setCacheBehavior", params)
  end

  @doc """
  Sets extra headers to send with every request.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the headers.
  - `:user_contexts` - List of user context IDs to scope the headers.
  """
  @spec set_extra_headers(GenServer.server(), [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_extra_headers(conn, headers, opts \\ []) do
    params = %{headers: headers}
    params = put_opt(params, :contexts, opts)
    params = put_opt(params, :user_contexts, opts, :userContexts)
    Connection.send_command(conn, "network.setExtraHeaders", params)
  end

  ## Private helpers

  defp put_opt(params, key, opts, json_key \\ nil) do
    json_key = json_key || key

    case Keyword.get(opts, key) do
      nil -> params
      value -> Map.put(params, json_key, value)
    end
  end
end
