# Launches a Browser, prints its process group, then idles until killed.
opts = if System.get_env("BBD_FAKE_FIREFOX"), do: [browser_path: Path.expand("dev/launcher_prototype/fake_firefox.sh")], else: []
{:ok, b} = Bibbidi.Browser.start_link(opts)
_ = GenServer.call(b, :url, 60_000)
%{launched: %{os_pid: pgid}, profile_dir: dir} = :sys.get_state(b)
IO.puts("VICTIM beam=#{System.pid()} pgid=#{pgid} profile=#{dir}")
Process.sleep(:infinity)
