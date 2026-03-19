defmodule Bibbidi.Browser do
  @moduledoc """
  GenServer that owns a browser OS process via `Port.open`.

  When this process terminates for any reason (normal shutdown, crash, supervisor
  killing it), `terminate/2` kills the entire browser process tree. No orphans.

  Users supervise this process themselves — Bibbidi imposes no supervision tree.

  ## Usage

      {:ok, browser} = Bibbidi.Browser.start_link(headless: true)
      url = Bibbidi.Browser.url(browser)
      {:ok, conn} = Bibbidi.Connection.start_link(url: url)

  ## Options

  - `:headless` — boolean, default `true`. Set `false` for headed mode.
  - `:browser_path` — custom binary path. Falls back to auto-detect.
  - `:port` — debugging port number. Default: random available port.
  """

  use GenServer

  @firefox_paths [
    # macOS
    "/Applications/Firefox.app/Contents/MacOS/firefox",
    # Linux
    "firefox"
  ]

  @launch_timeout 15_000

  ## Client API

  @doc """
  Starts a browser process linked to the caller.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, browser_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, browser_opts, gen_opts)
  end

  @doc """
  Returns the BiDi WebSocket URL for this browser.
  """
  @spec url(GenServer.server()) :: String.t()
  def url(browser) do
    GenServer.call(browser, :url)
  end

  @doc """
  Gracefully stops the browser process. The browser OS process is killed in `terminate/2`.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(browser) do
    GenServer.stop(browser)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    headless = Keyword.get(opts, :headless, true)
    browser_path = Keyword.get(opts, :browser_path)
    port_number = Keyword.get(opts, :port, random_port())

    path = browser_path || find_firefox()

    case path do
      nil ->
        {:stop, :browser_not_found}

      path ->
        {:ok, {path, port_number, headless}, {:continue, :launch}}
    end
  end

  @impl true
  def handle_continue(:launch, {path, port_number, headless}) do
    profile_dir = temp_dir()
    File.mkdir_p!(profile_dir)

    args =
      if headless,
        do: ["--headless"],
        else: []

    args =
      args ++
        [
          "--remote-debugging-port",
          to_string(port_number),
          "--profile",
          profile_dir
        ]

    port = Port.open({:spawn_executable, path}, [:binary, :stderr_to_stdout, args: args])

    os_pid =
      case :erlang.port_info(port, :os_pid) do
        {:os_pid, pid} -> pid
        :undefined -> nil
      end

    case wait_for_bidi_url(port, "") do
      {:ok, bidi_url} ->
        {:noreply, %{port: port, os_pid: os_pid, url: bidi_url, profile_dir: profile_dir}}

      {:error, reason} ->
        kill_tree(os_pid)
        {:stop, reason, nil}
    end
  end

  @impl true
  def handle_call(:url, _from, state) do
    {:reply, state.url, state}
  end

  @impl true
  def handle_info({port, {:data, _data}}, %{port: port} = state) do
    # Discard browser stdout/stderr after launch
    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, nil), do: :ok

  def terminate(_reason, state) do
    if state.port do
      try do
        Port.close(state.port)
      catch
        _, _ -> :ok
      end
    end

    kill_tree(state.os_pid)
    cleanup_profile(state.profile_dir)
    :ok
  end

  ## Private

  defp wait_for_bidi_url(port, buffer) do
    receive do
      {^port, {:data, data}} ->
        buffer = buffer <> data

        case Regex.run(~r{WebDriver BiDi listening on (ws://[^\s]+)}, buffer) do
          [_, url] ->
            {:ok, url <> "/session"}

          nil ->
            wait_for_bidi_url(port, buffer)
        end
    after
      @launch_timeout ->
        {:error, {:browser_launch_timeout, buffer}}
    end
  end

  defp find_firefox do
    Enum.find(@firefox_paths, &System.find_executable/1)
  end

  defp random_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp temp_dir do
    Path.join(System.tmp_dir!(), "bibbidi-firefox-#{System.unique_integer([:positive])}")
  end

  defp kill_tree(nil), do: :ok

  defp kill_tree(pid) do
    # Collect children before killing parent, since dead processes have no children
    children =
      case System.cmd("pgrep", ["-P", to_string(pid)], stderr_to_stdout: true) do
        {children_str, 0} ->
          children_str |> String.split("\n", trim: true) |> Enum.map(&String.to_integer/1)

        {_, _} ->
          []
      end

    Enum.each(children, &kill_tree/1)
    System.cmd("kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)
  catch
    _, _ -> :ok
  end

  defp cleanup_profile(nil), do: :ok

  defp cleanup_profile(dir) do
    File.rm_rf(dir)
  catch
    _, _ -> :ok
  end
end
