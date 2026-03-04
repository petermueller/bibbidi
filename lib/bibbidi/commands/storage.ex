defmodule Bibbidi.Commands.Storage do
  @moduledoc """
  Command builders for the `storage` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Gets cookies matching the given filter.

  ## Options

  - `:filter` - A cookie filter map (e.g. `%{name: "session_id"}`).
  - `:partition` - A partition descriptor map.
  """
  @spec get_cookies(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_cookies(conn, opts \\ []) do
    params = %{}
    params = put_opt(params, :filter, opts)
    params = put_opt(params, :partition, opts)
    Connection.send_command(conn, "storage.getCookies", params)
  end

  @doc """
  Sets a cookie.

  `cookie` is a partial cookie map with at least `:name`, `:value`, and `:domain`.

  ## Options

  - `:partition` - A partition descriptor map.
  """
  @spec set_cookie(GenServer.server(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def set_cookie(conn, cookie, opts \\ []) do
    params = %{cookie: cookie}
    params = put_opt(params, :partition, opts)
    Connection.send_command(conn, "storage.setCookie", params)
  end

  @doc """
  Deletes cookies matching the given filter.

  ## Options

  - `:filter` - A cookie filter map.
  - `:partition` - A partition descriptor map.
  """
  @spec delete_cookies(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def delete_cookies(conn, opts \\ []) do
    params = %{}
    params = put_opt(params, :filter, opts)
    params = put_opt(params, :partition, opts)
    Connection.send_command(conn, "storage.deleteCookies", params)
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
