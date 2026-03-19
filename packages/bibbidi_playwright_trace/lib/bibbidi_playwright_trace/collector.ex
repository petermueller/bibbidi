defmodule BibbidiPlaywrightTrace.Collector do
  @moduledoc """
  GenServer that attaches to Bibbidi telemetry events and accumulates
  trace data suitable for writing a Playwright-compatible trace zip.

  Listens to:
  - `[:bibbidi, :command, :start]` — records a `before` trace event
  - `[:bibbidi, :command, :stop]` — records an `after` trace event, correlating by command ref
  - `[:bibbidi, :event, :received]` — records a BiDi event

  ## Options

  - `:browser_name` — browser name for context-options header (default: `"unknown"`)
  - `:platform` — platform string (default: detected from OS)
  - `:viewport` — `{width, height}` or `%{width: w, height: h}` (optional)
  - `:connection` — filter to only trace commands on this connection pid (optional)
  - `:reducer` — MFA or MFArgs tuple for user-defined event transformation (optional)

  ## Reducer

  When provided, the reducer is called for each completed before/after pair:

      # MFA — called as MyModule.reduce(before_event, after_event)
      reducer: {MyModule, :reduce, 2}

      # MFArgs — called as MyModule.reduce(before_event, after_event, some: :opt)
      reducer: {MyModule, :reduce, [some: :opt]}

  Must return one of:
  - `{before_event, after_event}` — possibly modified events
  - `[{before, after}, ...]` — expand one command into multiple logical actions
  - `:skip` — omit this command from the trace
  """

  use GenServer

  alias BibbidiPlaywrightTrace.Writer

  defstruct [
    :handler_id,
    :connection,
    :reducer,
    context_opts: [],
    call_counter: 0,
    pending: %{},
    trace_events: [],
    resources: %{}
  ]

  @type option ::
          {:browser_name, String.t()}
          | {:platform, String.t()}
          | {:viewport,
             {pos_integer(), pos_integer()} | %{width: pos_integer(), height: pos_integer()}}
          | {:connection, pid()}
          | {:reducer, {module(), atom(), non_neg_integer()} | {module(), atom(), list()}}

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, collector_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, collector_opts, gen_opts)
  end

  @doc """
  Returns the accumulated trace events and resources.
  """
  @spec get_trace(GenServer.server()) :: {[map()], %{String.t() => binary()}}
  def get_trace(collector) do
    GenServer.call(collector, :get_trace)
  end

  @doc """
  Stops the collector and returns the accumulated trace data.
  """
  @spec stop(GenServer.server()) :: {[map()], %{String.t() => binary()}}
  def stop(collector) do
    GenServer.call(collector, :stop)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    handler_id = "bibbidi_playwright_trace_#{:erlang.unique_integer([:positive])}"

    context_opts =
      Keyword.take(opts, [:browser_name, :platform, :viewport])

    state = %__MODULE__{
      handler_id: handler_id,
      connection: Keyword.get(opts, :connection),
      reducer: Keyword.get(opts, :reducer),
      context_opts: context_opts
    }

    collector = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:bibbidi, :command, :start],
        [:bibbidi, :command, :stop],
        [:bibbidi, :event, :received]
      ],
      &__MODULE__.handle_telemetry_event/4,
      collector
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_trace, _from, state) do
    {events, resources} = build_trace(state)
    {:reply, {events, resources}, state}
  end

  def handle_call(:stop, _from, state) do
    {events, resources} = build_trace(state)
    {:stop, :normal, {events, resources}, state}
  end

  @impl true
  def handle_cast({:command_start, metadata, measurements}, state) do
    if filtered?(state, metadata) do
      {:noreply, state}
    else
      call_id = "call@#{state.call_counter + 1}"
      start_time = wall_time(measurements)

      params = stringify_keys(metadata.params)
      before = Writer.before_event(call_id, start_time, metadata.method, params)

      # Key pending by command struct ref for correlation
      command_ref = command_ref(metadata.command)

      state = %{
        state
        | call_counter: state.call_counter + 1,
          pending: Map.put(state.pending, command_ref, {call_id, before})
      }

      {:noreply, state}
    end
  end

  def handle_cast({:command_stop, metadata, measurements}, state) do
    command_ref = command_ref(metadata.command)

    case Map.pop(state.pending, command_ref) do
      {nil, _pending} ->
        {:noreply, state}

      {{call_id, before}, pending} ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        end_time = before["startTime"] + duration_ms
        result = metadata.result

        after_evt = Writer.after_event(call_id, end_time, result)

        {events, resources} = apply_reducer(state.reducer, before, after_evt)
        {events, resources} = maybe_extract_screenshot(events, resources, result)

        state = %{
          state
          | pending: pending,
            trace_events: state.trace_events ++ events,
            resources: Map.merge(state.resources, resources)
        }

        {:noreply, state}
    end
  end

  def handle_cast({:bidi_event, metadata, measurements}, state) do
    if filtered?(state, metadata) do
      {:noreply, state}
    else
      time = wall_time(measurements)
      event = Writer.bidi_event(time, metadata.event, metadata.params)
      {:noreply, %{state | trace_events: state.trace_events ++ [event]}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  ## Telemetry handler (called in the emitting process, sends to collector)

  @doc false
  def handle_telemetry_event([:bibbidi, :command, :start], measurements, metadata, collector) do
    GenServer.cast(collector, {:command_start, metadata, measurements})
  end

  def handle_telemetry_event([:bibbidi, :command, :stop], measurements, metadata, collector) do
    GenServer.cast(collector, {:command_stop, metadata, measurements})
  end

  def handle_telemetry_event([:bibbidi, :event, :received], measurements, metadata, collector) do
    GenServer.cast(collector, {:bidi_event, metadata, measurements})
  end

  ## Private

  defp build_trace(state) do
    context = Writer.context_options(state.context_opts)
    events = [context | state.trace_events]
    {events, state.resources}
  end

  defp filtered?(%{connection: nil}, _metadata), do: false

  defp filtered?(%{connection: conn}, metadata) do
    metadata.connection != conn
  end

  defp command_ref(command) do
    :erlang.phash2(command, 1_000_000_000)
  end

  defp apply_reducer(nil, before, after_evt) do
    {[before, after_evt], %{}}
  end

  defp apply_reducer({mod, fun, arity}, before, after_evt) when is_integer(arity) do
    result = apply(mod, fun, [before, after_evt])
    normalize_reducer_result(result)
  end

  defp apply_reducer({mod, fun, args}, before, after_evt) when is_list(args) do
    result = apply(mod, fun, [before, after_evt, args])
    normalize_reducer_result(result)
  end

  defp normalize_reducer_result(:skip) do
    {[], %{}}
  end

  defp normalize_reducer_result({before, after_evt}) when is_map(before) and is_map(after_evt) do
    {[before, after_evt], %{}}
  end

  defp normalize_reducer_result(pairs) when is_list(pairs) do
    events =
      Enum.flat_map(pairs, fn {before, after_evt} -> [before, after_evt] end)

    {events, %{}}
  end

  defp maybe_extract_screenshot(events, resources, {:ok, response})
       when is_map(response) do
    case response do
      %{"data" => base64_data} ->
        # This looks like a captureScreenshot response
        # Find the before event to get a pageId (from params.context)
        page_id =
          events
          |> Enum.find(&(&1["type"] == "before"))
          |> case do
            %{"params" => %{"context" => ctx}} -> ctx
            _ -> "page@unknown"
          end

        timestamp =
          events
          |> Enum.find(&(&1["type"] == "after"))
          |> case do
            %{"endTime" => t} -> t
            _ -> System.system_time(:millisecond)
          end

        {frame_event, sha1, binary} =
          Writer.screencast_frame(page_id, timestamp, base64_data)

        {events ++ [frame_event], Map.put(resources, sha1, binary)}

      _ ->
        {events, resources}
    end
  end

  defp maybe_extract_screenshot(events, resources, _result) do
    {events, resources}
  end

  defp wall_time(%{system_time: system_time}) do
    System.convert_time_unit(system_time, :native, :millisecond)
  end

  defp wall_time(_measurements) do
    System.system_time(:millisecond)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(other), do: other
end
