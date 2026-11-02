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

  alias Bibbidi.Launcher.PortSh

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
    # PROTOTYPE (#8): trap exits so terminate/2 runs when a linked process
    # (the caller, a Connection, ExUnit's setup_all process) exits.
    Process.flag(:trap_exit, true)
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
    # PROTOTYPE (#8): one temp root holds the profile AND Firefox's app-data
    # dir. On macOS 27 ~/Library/Application Support/Firefox is TCC-protected
    # and Firefox >= 155 still opens it during profile startup even with
    # --profile; from a parent without Full Disk Access that fails with
    # "Could not find profile folder" (157) or a busy-spin in the error dialog
    # loop (144, headless). MOZ_APP_DATA redirects it. The wrapper removes
    # the whole root on the BEAM-death path.
    temp_root = temp_dir()
    profile_dir = Path.join(temp_root, "profile")
    app_data_dir = Path.join(temp_root, "appdata")
    File.mkdir_p!(profile_dir)
    File.mkdir_p!(app_data_dir)

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

    {:ok, launched} =
      PortSh.launch(path, args, cleanup_dir: temp_root, env: [{"MOZ_APP_DATA", app_data_dir}])

    case wait_for_bidi_url(launched, "") do
      {:ok, bidi_url} ->
        {:noreply, %{launched: launched, url: bidi_url, profile_dir: temp_root}}

      {:error, reason} ->
        PortSh.stop(launched)
        cleanup_profile(temp_root)
        {:stop, reason, nil}
    end
  end

  @impl true
  def handle_call(:url, _from, state) do
    {:reply, state.url, state}
  end

  @impl true
  def handle_info(message, %{launched: launched} = state) do
    case PortSh.classify(launched, message) do
      # Discard browser stdout/stderr after launch
      {:output, _data} -> {:noreply, state}
      # Browser died on its own (crash, or killed from outside)
      {:exited, status} -> {:stop, {:browser_exited, status}, %{state | launched: nil}}
      :ignore -> {:noreply, state}
      :other -> handle_other(message, state)
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # A linked process (other than our parent, which gen_server handles itself)
  # exited: take the browser down with it.
  defp handle_other({:EXIT, _pid, reason}, state), do: {:stop, reason, state}
  defp handle_other(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, nil), do: :ok

  def terminate(_reason, %{launched: nil} = state) do
    cleanup_profile(state.profile_dir)
    :ok
  end

  def terminate(_reason, state) do
    PortSh.stop(state.launched)
    cleanup_profile(state.profile_dir)
    :ok
  end

  ## Private

  defp wait_for_bidi_url(launched, buffer) do
    receive do
      message ->
        case PortSh.classify(launched, message) do
          {:output, data} ->
            buffer = buffer <> data

            case Regex.run(~r{WebDriver BiDi listening on (ws://[^\s]+)}, buffer) do
              [_, url] -> {:ok, url <> "/session"}
              nil -> wait_for_bidi_url(launched, buffer)
            end

          {:exited, status} ->
            {:error, {:browser_exited, status, buffer}}

          :ignore ->
            wait_for_bidi_url(launched, buffer)

          :other ->
            # Re-queue anything that is not ours (e.g. an {:EXIT, pid, _} from a
            # linked process) so the main loop sees it after launch.
            send(self(), message)
            wait_for_bidi_url(launched, buffer)
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

  defp cleanup_profile(nil), do: :ok

  defp cleanup_profile(dir) do
    File.rm_rf(dir)
  catch
    _, _ -> :ok
  end
end
