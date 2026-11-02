defmodule Bibbidi.Launcher.PortSh do
  @moduledoc """
  PROTOTYPE (issue #8) — pure-Elixir default Launcher: `Port.open` through the
  bundled `priv/launcher.sh` wrapper.

  The wrapper is the process-group leader of everything it starts (Erlang's
  `erl_child_setup` gives every port child its own process group), so:

    * `stop/2` signals the whole group from Elixir: TERM, wait up to `grace_ms`
      for the wrapper's exit status, then KILL. Synchronous: when it returns,
      the group is gone.
    * if nothing on the Elixir side ever runs (`:brutal_kill`, BEAM SIGKILL),
      the wrapper notices stdin EOF and does the same TERM -> grace -> KILL on
      its own, then removes `cleanup_dir`.

  The functions here are the candidate callbacks for the Launcher behaviour;
  see the resolution comment on issue #8.
  """

  defstruct [:port, :os_pid, :grace_ms]

  @type t :: %__MODULE__{port: port(), os_pid: pos_integer(), grace_ms: pos_integer()}

  @default_grace_ms 2_000

  @doc """
  Launches `executable` with `args` through the wrapper.

  Options:
    * `:grace_ms` — TERM -> KILL grace period (default #{@default_grace_ms}).
      Passed to the wrapper as whole seconds (rounded up).
    * `:cleanup_dir` — directory the wrapper removes after the group is dead.
      The wrapper only honours paths whose basename starts with `bibbidi-`.
    * `:env` — extra environment for the executable, `[{"NAME", "value"}]`.
  """
  @spec launch(Path.t(), [String.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def launch(executable, args, opts \\ []) do
    grace_ms = Keyword.get(opts, :grace_ms, @default_grace_ms)
    grace_s = Integer.to_string(div(grace_ms + 999, 1000))

    cleanup_env =
      case Keyword.get(opts, :cleanup_dir) do
        nil -> []
        dir -> [{~c"BIBBIDI_LAUNCHER_RM_RF", String.to_charlist(dir)}]
      end

    extra_env =
      for {k, v} <- Keyword.get(opts, :env, []),
          do: {String.to_charlist(k), String.to_charlist(v)}

    env = [{~c"BIBBIDI_LAUNCHER_GRACE", String.to_charlist(grace_s)} | cleanup_env] ++ extra_env

    port =
      Port.open({:spawn_executable, wrapper_path()}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [executable | args],
        env: env
      ])

    case :erlang.port_info(port, :os_pid) do
      {:os_pid, os_pid} -> {:ok, %__MODULE__{port: port, os_pid: os_pid, grace_ms: grace_ms}}
      :undefined -> {:error, :no_os_pid}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Classifies a message received by the Port owner.

    * `{:output, binary}` — stdout/stderr of the wrapper and its child
    * `{:exited, status}` — the wrapper exited (child gone, group swept)
    * `:ignore` — the trailing `{:EXIT, port, _}` seen under `trap_exit`
    * `:other` — not ours
  """
  @spec classify(t(), term()) :: {:output, binary()} | {:exited, integer()} | :ignore | :other
  def classify(%__MODULE__{port: port}, {port, {:data, data}}), do: {:output, data}
  def classify(%__MODULE__{port: port}, {port, {:exit_status, status}}), do: {:exited, status}
  def classify(%__MODULE__{port: port}, {:EXIT, port, _reason}), do: :ignore
  def classify(_launched, _message), do: :other

  @doc """
  Stops the launched process group: TERM, wait for the wrapper's exit status
  up to the grace period, then KILL. Returns when the group is gone.
  """
  @spec stop(t()) :: :ok | {:ok, :killed} | {:ok, {:exited, integer()}}
  def stop(%__MODULE__{} = launched), do: stop(launched, launched.grace_ms)

  @spec stop(t(), timeout()) :: :ok | {:ok, :killed} | {:ok, {:exited, integer()}}
  def stop(%__MODULE__{port: port, os_pid: pgid} = launched, grace_ms) do
    result =
      if alive?(launched) do
        signal_group(pgid, "TERM")

        receive do
          {^port, {:exit_status, status}} -> {:ok, {:exited, status}}
        after
          grace_ms ->
            signal_group(pgid, "KILL")
            wait_dead(launched, 1_000)
            {:ok, :killed}
        end
      else
        :ok
      end

    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    flush(port)
    result
  end

  @doc "True while any process in the launched group exists."
  @spec alive?(t()) :: boolean()
  def alive?(%__MODULE__{os_pid: pgid}) do
    case System.cmd("kill", ["-0", "-#{pgid}"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc "Absolute path of the bundled wrapper script."
  @spec wrapper_path() :: Path.t()
  def wrapper_path do
    case :code.priv_dir(:bibbidi) do
      {:error, _} -> Path.expand("priv/launcher.sh")
      dir -> Path.join(List.to_string(dir), "launcher.sh")
    end
  end

  defp signal_group(pgid, sig) do
    _ = System.cmd("kill", ["-#{sig}", "-#{pgid}"], stderr_to_stdout: true)
    :ok
  end

  defp wait_dead(launched, budget_ms) when budget_ms <= 0, do: alive?(launched)

  defp wait_dead(launched, budget_ms) do
    if alive?(launched) do
      Process.sleep(20)
      wait_dead(launched, budget_ms - 20)
    else
      false
    end
  end

  defp flush(port) do
    receive do
      {^port, _} -> flush(port)
      {:EXIT, ^port, _} -> flush(port)
    after
      0 -> :ok
    end
  end
end
