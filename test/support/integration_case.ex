defmodule Bibbidi.IntegrationCase do
  @moduledoc """
  Case template for integration tests.

  ## Usage

      use Bibbidi.IntegrationCase

  This automatically:
  - Tags the module with `@moduletag :integration`
  - Launches a browser (or connects to `BBD_BROWSER_URL`) in `setup_all`
  - Creates a single connection + session shared across tests
  - Cleans up on exit
  """

  use ExUnit.CaseTemplate

  alias Bibbidi.Connection
  alias Bibbidi.Session

  using do
    quote do
      alias Bibbidi.Commands.BrowsingContext
      alias Bibbidi.Connection
      alias Bibbidi.Session

      @moduletag :integration
    end
  end

  setup_all _context do
    {conn, browser} =
      case System.get_env("BBD_BROWSER_URL") do
        nil ->
          headless = is_nil(System.get_env("BBD_DEBUG"))
          {:ok, browser} = Bibbidi.Browser.start_link(headless: headless)
          {:ok, conn} = Connection.start_link(browser: browser)
          {conn, browser}

        url ->
          {:ok, conn} = Connection.start_link(url: url)
          {conn, nil}
      end

    {:ok, _capabilities} = Session.new(conn)

    on_exit(fn ->
      try do
        Session.end_session(conn)
        Connection.close(conn)
      catch
        :exit, _ -> :ok
      end

      if browser, do: Bibbidi.Browser.stop(browser)
    end)

    %{conn: conn}
  end
end
