defmodule Bibbidi.Connection do
  @moduledoc """
  GenServer that manages a WebDriver BiDi WebSocket connection.

  Users supervise this process themselves — Bibbidi imposes no supervision tree.

  ## Usage

      {:ok, conn} = Bibbidi.Connection.start_link(url: "ws://localhost:9222/session")

      {:ok, result} = Bibbidi.Connection.send_command(conn, "session.status", %{})

      :ok = Bibbidi.Connection.subscribe(conn, "browsingContext.load")
      # Caller receives the parsed event struct directly:
      #   %Bibbidi.Events.BrowsingContext.Load{context: ..., url: ...}

  ## Event-message shape

  By default subscribers receive the raw parsed struct (see `Bibbidi.Events.parse/2`).
  Pattern-match on the struct directly or use `Bibbidi.Events.Guards` for category
  predicates (`is_bibbidi_event/1`, `is_bibbidi_log_event/1`, ...).

  Override per-subscribe with `wrap:` to re-shape each event before delivery.
  Both a 1-arity function and an `{module, function, extra_args}` tuple are
  accepted; the tuple form prepends the event as the first argument before
  the configured extras:

      Bibbidi.Connection.subscribe(conn, "log.entryAdded", self(),
        wrap: fn ev -> {:my_app, ev} end)
      # Receives: {:my_app, %Bibbidi.Events.Log.EntryAdded{...}}

      Bibbidi.Connection.subscribe(conn, "log.entryAdded", self(),
        wrap: {MyApp.Events, :wrap, [:my_app]})
      # Calls MyApp.Events.wrap(event, :my_app); receives that return value.

  Or set an app-wide default in your config. Because function captures don't
  survive serialisation through `config.exs` / `runtime.exs`, this must be an
  MFA tuple:

      config :bibbidi, default_event_wrapper: {MyApp.Events, :wrap, []}

  Resolution order: per-subscribe `:wrap` -> `:default_event_wrapper` env ->
  `{Function, :identity, []}`. The wrap is applied in this GenServer's process
  before `send/2`, so keep it cheap.
  """

  use GenServer

  alias Bibbidi.Protocol

  @doc """
  Callback for executing an `Encodable` command struct.

  This behaviour is used by generated facade modules via the `:connection_mod`
  option, defaulting to this module. Override in tests with a Mox mock.
  """
  @callback execute(GenServer.server(), Bibbidi.Encodable.t(), keyword()) ::
              {:ok, map()} | {:error, term()}

  @behaviour __MODULE__

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

  @doc """
  Sends a BiDi command directly by method name and params map.

  Most callers should prefer `execute/2`, which accepts `Encodable` command
  structs and automatically emits telemetry events. This function is useful
  when you need to send a command that doesn't have a generated struct yet
  (e.g. a new spec addition or a vendor extension), or when you want full
  control over the wire payload.

  Note that `send_command/4` does **not** emit telemetry or go through the
  `Encodable` protocol — if you need those, call `execute/2` instead or
  handle them yourself.

  ## Options

  - `:timeout` — GenServer call timeout in milliseconds (default: `30_000`)

  ## Example

      # Send a vendor-specific command not yet in the spec
      Connection.send_command(conn, "vendor.customCommand", %{key: "value"})
  """
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
  @impl true
  @spec execute(GenServer.server(), Bibbidi.Encodable.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute(conn, command, opts \\ []) do
    method = Bibbidi.Encodable.method(command)
    params = Bibbidi.Encodable.params(command)

    correlation = Bibbidi.Telemetry.Metadata.telemetry_metadata(command)

    metadata =
      Map.merge(
        %{command: command, method: method, params: params, connection: conn},
        correlation
      )

    :telemetry.span([:bibbidi, :command], metadata, fn ->
      result = send_command(conn, method, params, opts)
      {result, Map.put(metadata, :result, result)}
    end)
  end

  @typedoc """
  Shape accepted for the `:wrap` subscribe option (and the
  `:default_event_wrapper` application env).

  Either a 1-arity function, or an `{module, function, args}` tuple invoked
  with the event prepended to `args` — i.e. `apply(mod, fun, [event | args])`.
  """
  @type wrap_spec :: (struct() -> term()) | {module(), atom(), [term()]}

  @doc """
  Subscribes the given process (default: caller) to events matching `method`.

  The subscriber receives the parsed event struct (see `Bibbidi.Events.parse/2`),
  optionally re-shaped by a wrap. See module doc for the resolution order and
  trade-offs.

  ## Options

  - `:wrap` — a `t:wrap_spec/0`. Defaults to the `:default_event_wrapper`
    Application env or `{Function, :identity, []}`.
  """
  @spec subscribe(GenServer.server(), String.t(), pid(), [{:wrap, wrap_spec()}]) :: :ok
  def subscribe(conn, method, pid \\ self(), opts \\ []) do
    wrap = resolve_wrap(opts)
    GenServer.call(conn, {:subscribe, method, pid, wrap})
  end

  @doc """
  Unsubscribes the given process from events matching `method`.
  """
  @spec unsubscribe(GenServer.server(), String.t(), pid()) :: :ok
  def unsubscribe(conn, method, pid \\ self()) do
    GenServer.call(conn, {:unsubscribe, method, pid})
  end

  # Resolves the wrap function for a subscribe call.
  # Per-subscribe `:wrap` > `:default_event_wrapper` env > {Function, :identity, []}.
  defp resolve_wrap(opts) do
    case Keyword.get(opts, :wrap) do
      nil ->
        :bibbidi
        |> Application.get_env(:default_event_wrapper, {Function, :identity, []})
        |> to_wrap_fn()

      spec ->
        to_wrap_fn(spec)
    end
  end

  defp to_wrap_fn(fun) when is_function(fun, 1), do: fun

  defp to_wrap_fn({mod, fun, args})
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    fn event -> apply(mod, fun, [event | args]) end
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

  def handle_call({:subscribe, method, pid, wrap}, _from, state) do
    monitored =
      if MapSet.member?(state.monitored, pid) do
        state.monitored
      else
        Process.monitor(pid)
        MapSet.put(state.monitored, pid)
      end

    # A re-subscribe with a different wrap fn replaces the previous one for
    # this (method, pid) pair.
    subs =
      Map.update(state.subscribers, method, %{pid => wrap}, &Map.put(&1, pid, wrap))

    {:reply, :ok, %{state | subscribers: subs, monitored: monitored}}
  end

  def handle_call({:unsubscribe, method, pid}, _from, state) do
    subs =
      case Map.get(state.subscribers, method) do
        nil ->
          state.subscribers

        pid_to_wrap ->
          new_map = Map.delete(pid_to_wrap, pid)

          if map_size(new_map) == 0,
            do: Map.delete(state.subscribers, method),
            else: Map.put(state.subscribers, method, new_map)
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
      |> Enum.map(fn {method, pid_to_wrap} -> {method, Map.delete(pid_to_wrap, pid)} end)
      |> Enum.reject(fn {_method, pid_to_wrap} -> map_size(pid_to_wrap) == 0 end)
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
    # Bibbidi.Events.parse/2 always returns a struct (either a typed
    # event or %Bibbidi.Events.Unknown{}); telemetry_metadata/1 handles
    # non-derived structs (like Unknown) gracefully by returning %{}.
    parsed = Bibbidi.Events.parse(method, params)
    correlation = Bibbidi.Telemetry.Metadata.telemetry_metadata(parsed)

    :telemetry.execute(
      [:bibbidi, :event, :received],
      %{system_time: System.system_time()},
      Map.merge(%{event: method, params: parsed, connection: self()}, correlation)
    )

    case Map.get(state.subscribers, method) do
      nil ->
        :ok

      pid_to_wrap ->
        Enum.each(pid_to_wrap, fn {pid, wrap} -> send(pid, wrap.(parsed)) end)
    end
  end
end
