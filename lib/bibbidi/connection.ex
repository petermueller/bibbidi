defmodule Bibbidi.Connection do
  @moduledoc """
  GenServer that manages a WebDriver BiDi WebSocket connection.

  Users supervise this process themselves — Bibbidi imposes no supervision tree.

  ## Usage

      {:ok, conn} = Bibbidi.Connection.start_link(url: "ws://localhost:9222/session")

      {:ok, result} = Bibbidi.Connection.send_command(conn, "session.status", %{})

      :ok = Bibbidi.Connection.subscribe(conn, "browsingContext.load")
      # Caller receives: {:bibbidi_event, "browsingContext.load", params}
  """

  use GenServer

  alias Bibbidi.Protocol

  defstruct [
    :transport_mod,
    :transport_state,
    :url,
    command_id: 0,
    pending: %{},
    subscribers: %{},
    monitored: MapSet.new()
  ]

  @type option ::
          {:url, String.t()}
          | {:browser, GenServer.server()}
          | {:transport, module()}
          | {:transport_opts, keyword()}

  ## Client API

  @doc """
  Starts a connection process linked to the caller.
  """
  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, conn_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, conn_opts, gen_opts)
  end

  @doc false
  @spec send_command(GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def send_command(conn, method, params \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(conn, {:send_command, method, params}, timeout)
  end

  @doc """
  Executes an `Encodable` command struct and waits for the response.

  Emits telemetry events (see `Bibbidi.Telemetry`):
  - `[:bibbidi, :command, :start]`
  - `[:bibbidi, :command, :stop]`
  - `[:bibbidi, :command, :exception]`

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  """
  @spec execute(GenServer.server(), Bibbidi.Encodable.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute(conn, command, opts \\ []) do
    method = Bibbidi.Encodable.method(command)
    params = Bibbidi.Encodable.params(command)

    metadata = %{command: command, method: method, params: params, connection: conn}

    :telemetry.span([:bibbidi, :command], metadata, fn ->
      result = send_command(conn, method, params, opts)
      {result, Map.put(metadata, :result, result)}
    end)
  end

  @doc """
  Subscribes the given process (default: caller) to events matching `method`.

  The subscriber receives messages as `{:bibbidi_event, method, params}`.
  """
  @spec subscribe(GenServer.server(), String.t(), pid()) :: :ok
  def subscribe(conn, method, pid \\ self()) do
    GenServer.call(conn, {:subscribe, method, pid})
  end

  @doc """
  Unsubscribes the given process from events matching `method`.
  """
  @spec unsubscribe(GenServer.server(), String.t(), pid()) :: :ok
  def unsubscribe(conn, method, pid \\ self()) do
    GenServer.call(conn, {:unsubscribe, method, pid})
  end

  @doc """
  Closes the connection gracefully.
  """
  @spec close(GenServer.server()) :: :ok
  def close(conn) do
    GenServer.call(conn, :close)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    url =
      case Keyword.fetch(opts, :browser) do
        {:ok, browser} -> Bibbidi.Browser.url(browser)
        :error -> Keyword.fetch!(opts, :url)
      end

    transport_mod = Keyword.get(opts, :transport, Bibbidi.Transport.MintWS)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    uri = URI.parse(url)

    case transport_mod.connect(uri, transport_opts) do
      {:ok, transport_state} ->
        state = %__MODULE__{
          transport_mod: transport_mod,
          transport_state: transport_state,
          url: url
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:send_command, method, params}, from, state) do
    id = state.command_id
    json = Protocol.encode_command(id, method, params)

    case state.transport_mod.send_message(state.transport_state, json) do
      {:ok, transport_state} ->
        state = %{
          state
          | transport_state: transport_state,
            command_id: id + 1,
            pending: Map.put(state.pending, id, from)
        }

        {:noreply, state}

      {:error, transport_state, reason} ->
        {:reply, {:error, reason}, %{state | transport_state: transport_state}}
    end
  end

  def handle_call({:subscribe, method, pid}, _from, state) do
    monitored =
      if MapSet.member?(state.monitored, pid) do
        state.monitored
      else
        Process.monitor(pid)
        MapSet.put(state.monitored, pid)
      end

    subs = Map.update(state.subscribers, method, MapSet.new([pid]), &MapSet.put(&1, pid))
    {:reply, :ok, %{state | subscribers: subs, monitored: monitored}}
  end

  def handle_call({:unsubscribe, method, pid}, _from, state) do
    subs =
      case Map.get(state.subscribers, method) do
        nil ->
          state.subscribers

        set ->
          new_set = MapSet.delete(set, pid)

          if MapSet.size(new_set) == 0,
            do: Map.delete(state.subscribers, method),
            else: Map.put(state.subscribers, method, new_set)
      end

    {:reply, :ok, %{state | subscribers: subs}}
  end

  def handle_call(:close, _from, state) do
    case state.transport_mod.close(state.transport_state) do
      {:ok, transport_state} ->
        {:stop, :normal, :ok, %{state | transport_state: transport_state}}

      {:error, transport_state, _reason} ->
        {:stop, :normal, :ok, %{state | transport_state: transport_state}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subs =
      state.subscribers
      |> Enum.map(fn {method, set} -> {method, MapSet.delete(set, pid)} end)
      |> Enum.reject(fn {_method, set} -> MapSet.size(set) == 0 end)
      |> Map.new()

    {:noreply, %{state | subscribers: subs, monitored: MapSet.delete(state.monitored, pid)}}
  end

  def handle_info(message, state) do
    case state.transport_mod.handle_in(state.transport_state, message) do
      {:ok, transport_state, frames} ->
        state = %{state | transport_state: transport_state}
        state = process_frames(state, frames)
        {:noreply, state}

      :unknown ->
        {:noreply, state}
    end
  end

  ## Private

  defp process_frames(state, []), do: state

  defp process_frames(state, [{:text, data} | rest]) do
    state =
      case Protocol.decode_message(data) do
        {:command_response, id, result} ->
          case Map.pop(state.pending, id) do
            {nil, _pending} ->
              state

            {from, pending} ->
              GenServer.reply(from, {:ok, result})
              %{state | pending: pending}
          end

        {:error_response, id, error} ->
          case Map.pop(state.pending, id) do
            {nil, _pending} ->
              state

            {from, pending} ->
              GenServer.reply(from, {:error, error})
              %{state | pending: pending}
          end

        {:event, method, params} ->
          dispatch_event(state, method, params)
          state

        {:error, _reason} ->
          state
      end

    process_frames(state, rest)
  end

  defp process_frames(state, [:ping | rest]) do
    case state.transport_mod.send_pong(state.transport_state) do
      {:ok, transport_state} ->
        process_frames(%{state | transport_state: transport_state}, rest)

      {:error, transport_state, _reason} ->
        process_frames(%{state | transport_state: transport_state}, rest)
    end
  end

  defp process_frames(state, [{:close, _code, _reason} | _rest]) do
    # Remote closed — reply to all pending with error
    for {_id, from} <- state.pending do
      GenServer.reply(from, {:error, :connection_closed})
    end

    %{state | pending: %{}}
  end

  defp process_frames(state, [_other | rest]) do
    process_frames(state, rest)
  end

  defp dispatch_event(state, method, params) do
    :telemetry.execute(
      [:bibbidi, :event, :received],
      %{system_time: System.system_time()},
      %{event: method, params: params, connection: self()}
    )

    case Map.get(state.subscribers, method) do
      nil -> :ok
      pids -> Enum.each(pids, &send(&1, {:bibbidi_event, method, params}))
    end
  end
end
