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
    Connection.execute(conn, %__MODULE__.GetCookies{
      filter: opts[:filter],
      partition: opts[:partition]
    })
  end

  @doc """
  Sets a cookie.

  `cookie` is a partial cookie map with at least `:name`, `:value`, and `:domain`.

  ## Options

  - `:partition` - A partition descriptor map.
  """
  @spec set_cookie(GenServer.server(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def set_cookie(conn, cookie, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetCookie{
      cookie: cookie,
      partition: opts[:partition]
    })
  end

  @doc """
  Deletes cookies matching the given filter.

  ## Options

  - `:filter` - A cookie filter map.
  - `:partition` - A partition descriptor map.
  """
  @spec delete_cookies(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def delete_cookies(conn, opts \\ []) do
    Connection.execute(conn, %__MODULE__.DeleteCookies{
      filter: opts[:filter],
      partition: opts[:partition]
    })
  end
end
