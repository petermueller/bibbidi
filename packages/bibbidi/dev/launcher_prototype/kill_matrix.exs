# Kill matrix for the PortSh Launcher prototype (issue #8).
#
#   mix run dev/launcher_prototype/kill_matrix.exs            # real Firefox
#   BBD_FAKE_FIREFOX=1 mix run dev/launcher_prototype/kill_matrix.exs
#
# Cases 1-3 run here; case 4 (kill -9 of the BEAM) is dev/launcher_prototype/beam_kill9.sh.
defmodule KillMatrix do
  @grace 2_000

  def browser_opts do
    if System.get_env("BBD_FAKE_FIREFOX"),
      do: [browser_path: Path.expand("dev/launcher_prototype/fake_firefox.sh")],
      else: []
  end

  def group(pgid) do
    {out, _} = System.cmd("sh", ["-c", "ps -A -o pid=,pgid=,comm= | awk '$2==#{pgid}'"])
    String.split(out, "\n", trim: true)
  end

  def firefox_global do
    {out, _} = System.cmd("sh", ["-c", "pgrep -f 'Firefox.app/Contents/MacOS|fake_firefox' | wc -l"])
    String.trim(out)
  end

  def wait_empty(pgid, budget) when budget <= 0, do: {:still_alive, group(pgid)}

  def wait_empty(pgid, budget) do
    case group(pgid) do
      [] -> :empty
      _ -> Process.sleep(50); wait_empty(pgid, budget - 50)
    end
  end

  def launch do
    {:ok, b} = Bibbidi.Browser.start_link(browser_opts())
    url = GenServer.call(b, :url, 60_000)
    %{launched: %{os_pid: pgid}} = :sys.get_state(b)
    {b, url, pgid}
  end

  def report(name, pgid, t0) do
    res = wait_empty(pgid, @grace + 3_000)
    ms = System.monotonic_time(:millisecond) - t0
    IO.puts("  #{name}: group #{pgid} -> #{inspect(res)} after #{ms} ms; firefox-ish procs on host: #{firefox_global()}")
  end

  def case_stop do
    IO.puts("1) GenServer.stop/1")
    {b, url, pgid} = launch()
    IO.puts("  url=#{url} group=#{length(group(pgid))} procs: #{inspect(group(pgid))}")
    t0 = System.monotonic_time(:millisecond)
    :ok = GenServer.stop(b)
    IO.puts("  stop returned after #{System.monotonic_time(:millisecond) - t0} ms; group now: #{inspect(group(pgid))}")
    report("stop", pgid, t0)
  end

  def case_linked_exit do
    IO.puts("2) linked process exits (setup_all shape: owner gets exit(:shutdown))")
    me = self()
    owner = spawn(fn ->
      {b, _url, pgid} = launch()
      send(me, {:ready, b, pgid})
      receive do :never -> :ok end
    end)
    {b, pgid} = receive do {:ready, b, pgid} -> {b, pgid} after 60_000 -> raise "launch timeout" end
    IO.puts("  group=#{length(group(pgid))}")
    t0 = System.monotonic_time(:millisecond)
    Process.exit(owner, :shutdown)
    ref = Process.monitor(b)
    receive do {:DOWN, ^ref, _, _, reason} -> IO.puts("  browser down (#{inspect(reason)}) after #{System.monotonic_time(:millisecond) - t0} ms; group now: #{inspect(group(pgid))}") after 10_000 -> IO.puts("  browser still up?!") end
    report("linked-exit", pgid, t0)
  end

  def case_brutal_kill do
    IO.puts("3) supervisor shutdown with :brutal_kill (terminate/2 never runs)")
    Process.flag(:trap_exit, true)
    child = %{id: :b, start: {Bibbidi.Browser, :start_link, [browser_opts()]}, shutdown: :brutal_kill}
    {:ok, sup} = Supervisor.start_link([child], strategy: :one_for_one)
    [{:b, b, _, _}] = Supervisor.which_children(sup)
    _ = GenServer.call(b, :url, 60_000)
    %{launched: %{os_pid: pgid}} = :sys.get_state(b)
    IO.puts("  group=#{length(group(pgid))}")
    t0 = System.monotonic_time(:millisecond)
    :ok = Supervisor.stop(sup)
    IO.puts("  supervisor stopped after #{System.monotonic_time(:millisecond) - t0} ms; group now: #{length(group(pgid))} procs (wrapper must notice EOF)")
    report("brutal-kill", pgid, t0)
  end
end

IO.puts("firefox-ish procs on host before: #{KillMatrix.firefox_global()}  (other sessions may own some)")
KillMatrix.case_stop()
KillMatrix.case_linked_exit()
KillMatrix.case_brutal_kill()
