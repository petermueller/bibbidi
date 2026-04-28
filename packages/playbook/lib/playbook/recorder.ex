defmodule Playbook.Recorder do
  @moduledoc """
  Records browser interactions by injecting JavaScript event listeners.

  Listeners emit events via `console.log("[PLAYBOOK]" + JSON)`, which arrive
  here as `log.entryAdded` BiDi events — no polling required.

  A preload script ensures listeners are re-injected on every new document,
  so navigations don't break the recording.

  Each event is appended in real time to a `.jsonl` file on disk, so a
  recording survives crashes and can be re-transcribed later.
  """

  use GenServer
  require Logger

  alias Playbook.LogEntry

  @log_marker "[PLAYBOOK]"

  # ── Public API ─────────────────────────────────────────────────

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Start a recording session with a name."
  def begin_session(name) do
    GenServer.call(__MODULE__, {:begin_session, name})
  end

  @doc "Add a free-text annotation to the log."
  def annotate(text) do
    GenServer.call(__MODULE__, {:annotate, text})
  end

  @doc "End the recording session and return the full log."
  def end_session do
    GenServer.call(__MODULE__, :end_session)
  end

  @doc "Get the current in-memory log (fast, useful for peek)."
  def get_log do
    GenServer.call(__MODULE__, :get_log)
  end

  @doc "Get the active or last session name."
  def session_name, do: GenServer.call(__MODULE__, :session_name)

  @doc "Get the path to the active or last raw .jsonl log file."
  def raw_log_path, do: GenServer.call(__MODULE__, :raw_log_path)

  @doc "Check if currently recording."
  def recording? do
    GenServer.call(__MODULE__, :recording?)
  rescue
    _ -> false
  end

  # ── GenServer callbacks ────────────────────────────────────────

  @impl true
  def init(_state) do
    {:ok,
     %{
       recording: false,
       session_name: nil,
       log: [],
       preload_script_id: nil,
       last_session_name: nil,
       raw_log_path: nil,
       last_raw_log_path: nil
     }}
  end

  @impl true
  def handle_call({:begin_session, name}, _from, state) do
    js = listener_js()
    fn_decl = "() => { #{js} }"

    with {:ok, _sub} <- Autopilot.Browser.subscribe(["log.entryAdded"]),
         {:ok, preload} <- Autopilot.Browser.add_preload_script(fn_decl),
         :ok <- inject_now(js) do
      script_id = extract_script_id(preload)
      raw_path = open_raw_log(name)

      Logger.info(
        "[Recorder] Started session: #{name} (preload=#{script_id}, raw=#{raw_path})"
      )

      {:reply, :ok,
       %{
         state
         | recording: true,
           session_name: name,
           log: [],
           preload_script_id: script_id,
           raw_log_path: raw_path
       }}
    else
      {:error, reason} ->
        Logger.error("[Recorder] Failed to start session: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:annotate, text}, _from, %{recording: true} = state) do
    entry = LogEntry.annotation(text)
    Logger.info("[Recorder] #{LogEntry.to_log_line(entry)}")

    raw_event = %{
      "type" => "annotation",
      "text" => text,
      "ts" => System.system_time(:millisecond)
    }

    append_raw_event(state.raw_log_path, raw_event)

    {:reply, :ok, %{state | log: state.log ++ [entry]}}
  end

  def handle_call({:annotate, _text}, _from, %{recording: false} = state) do
    {:reply, {:error, :not_recording}, state}
  end

  def handle_call(:end_session, _from, %{recording: true} = state) do
    if state.preload_script_id do
      case Autopilot.Browser.remove_preload_script(state.preload_script_id) do
        {:ok, _} ->
          :ok

        err ->
          Logger.warning("[Recorder] Could not remove preload script: #{inspect(err)}")
      end
    end

    remove_listeners()

    Logger.info(
      "[Recorder] Session ended: #{state.session_name} (#{length(state.log)} events, raw=#{state.raw_log_path})"
    )

    {:reply, {:ok, state.session_name, state.log},
      %{
        state
        | recording: false,
          last_session_name: state.session_name,
          last_raw_log_path: state.raw_log_path,
          session_name: nil,
          preload_script_id: nil,
          raw_log_path: nil
      }}
  end

  def handle_call(:end_session, _from, %{recording: false} = state) do
    {:reply, {:error, :not_recording}, state}
  end

  def handle_call(:get_log, _from, state) do
    {:reply, state.log, state}
  end

  def handle_call(:recording?, _from, state) do
    {:reply, state.recording, state}
  end

  def handle_call(:session_name, _from, state) do
    {:reply, state.session_name || state.last_session_name, state}
  end

  def handle_call(:raw_log_path, _from, state) do
    {:reply, state.raw_log_path || state.last_raw_log_path, state}
  end

  # ── BiDi event handler ─────────────────────────────────────────

  @impl true
  def handle_info(
        {:bibbidi_event, "log.entryAdded", %Bibbidi.Events.Log.EntryAdded{text: text}},
        state
      )
      when is_binary(text) do
    process_log_text(text, state)
  end

  def handle_info({:bibbidi_event, "log.entryAdded", %{"text" => text}}, state)
      when is_binary(text) do
    process_log_text(text, state)
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Log entry processing ───────────────────────────────────────

  defp process_log_text(text, %{recording: true} = state) do
    case String.split(text, @log_marker, parts: 2) do
      [_prefix, json] ->
        case Jason.decode(json) do
          {:ok, event} ->
            entry = parse_event(event)
            Logger.info("[Recorder] #{LogEntry.to_log_line(entry)}")
            append_raw_event(state.raw_log_path, event)
            {:noreply, %{state | log: state.log ++ [entry]}}

          {:error, reason} ->
            Logger.debug("[Recorder] Failed to decode event JSON: #{inspect(reason)}")
            {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  defp process_log_text(_text, state), do: {:noreply, state}

  # ── Event parsing ──────────────────────────────────────────────

  defp parse_event(%{"type" => "click"} = e) do
    LogEntry.click(e["x"], e["y"], e["selector"], e["tag"], e["text"])
  end

  defp parse_event(%{"type" => "input"} = e) do
    LogEntry.input(e["selector"], e["value"], e["sensitive"] || false)
  end

  defp parse_event(%{"type" => "navigation"} = e) do
    LogEntry.navigation(e["url"], e["title"])
  end

  defp parse_event(e) do
    LogEntry.annotation("Unknown event: #{inspect(e)}")
  end

  # ── Raw log persistence ────────────────────────────────────────

  defp open_raw_log(name) do
    dir = Application.get_env(:playbook, :playbook_output_dir, "./playbooks")
    File.mkdir_p!(dir)

    timestamp = format_timestamp(:calendar.local_time())
    base = sanitize(name)
    path = Path.join(dir, "#{base}_#{timestamp}_raw.jsonl")

    # Touch the file so it exists from the start
    File.write!(path, "")

    # Write a header line with metadata
    header = %{
      "type" => "session_header",
      "session_name" => name,
      "started_at" => timestamp
    }

    append_raw_event(path, header)
    path
  end

  defp append_raw_event(nil, _event), do: :ok

  defp append_raw_event(path, event) do
    line = Jason.encode!(event) <> "\n"
    File.write!(path, line, [:append])
  rescue
    e ->
      Logger.error("[Recorder] Failed to append event to #{path}: #{Exception.message(e)}")
      :ok
  end

  defp sanitize(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp format_timestamp({{y, mo, d}, {h, mi, s}}) do
    :io_lib.format("~4..0B~2..0B~2..0B_~2..0B~2..0B~2..0B", [y, mo, d, h, mi, s])
    |> IO.iodata_to_binary()
  end

  # ── JavaScript injection ───────────────────────────────────────

  defp listener_js do
    """
    (function() {
      if (window.__playbook_recorder) return 'already_injected';
      window.__playbook_recorder = true;

      function emit(evt) {
        try { console.log('#{@log_marker}' + JSON.stringify(evt)); } catch(e) {}
      }

      function buildSelector(el) {
        try {
          if (el.id) return '#' + el.id;
          if (el.name) return el.tagName.toLowerCase() + '[name="' + el.name + '"]';
          if (el.className && typeof el.className === 'string')
            return el.tagName.toLowerCase() + '.' + el.className.trim().split(/\\s+/).join('.');
          return el.tagName.toLowerCase();
        } catch(err) { return el.tagName || 'unknown'; }
      }

      function emitInput(el) {
        var sensitive = (el.type === 'password');
        emit({
          type: 'input',
          ts: Date.now(),
          selector: buildSelector(el),
          value: sensitive ? '***' : el.value,
          sensitive: sensitive
        });
      }

      function emitNav() {
        var url = window.location.href;
        if (!url || url === 'about:blank' || url === 'about:home') return;
        emit({ type: 'navigation', ts: Date.now(), url: url, title: document.title });
      }

      document.addEventListener('click', function(e) {
        var el = e.target;
        emit({
          type: 'click',
          ts: Date.now(),
          x: Math.round(e.clientX),
          y: Math.round(e.clientY),
          selector: buildSelector(el),
          tag: (el.tagName || '').toLowerCase(),
          text: (el.textContent || '').trim().slice(0, 80)
        });
      }, true);

      var inputTimers = new WeakMap();
      var DEBOUNCE_MS = 500;

      document.addEventListener('input', function(e) {
        var el = e.target;
        if (!el.tagName || !['INPUT','TEXTAREA','SELECT'].includes(el.tagName)) return;

        var existing = inputTimers.get(el);
        if (existing) clearTimeout(existing);

        var timer = setTimeout(function() {
          inputTimers.delete(el);
          emitInput(el);
        }, DEBOUNCE_MS);

        inputTimers.set(el, timer);
      }, true);

      document.addEventListener('blur', function(e) {
        var el = e.target;
        if (!el.tagName || !['INPUT','TEXTAREA','SELECT'].includes(el.tagName)) return;
        var timer = inputTimers.get(el);
        if (timer) {
          clearTimeout(timer);
          inputTimers.delete(el);
          emitInput(el);
        }
      }, true);

      var origPush = history.pushState;
      var origReplace = history.replaceState;
      history.pushState = function() {
        origPush.apply(this, arguments);
        emitNav();
      };
      history.replaceState = function() {
        origReplace.apply(this, arguments);
        emitNav();
      };
      window.addEventListener('popstate', emitNav);

      emitNav();

      return 'injected';
    })()
    """
  end

  defp inject_now(js) do
    case Autopilot.Browser.eval(js) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp remove_listeners do
    js = """
    (function() {
      window.__playbook_recorder = false;
      return 'removed';
    })()
    """

    Autopilot.Browser.eval(js)
  end

  defp extract_script_id(%{"script" => id}), do: id
  defp extract_script_id(id) when is_binary(id), do: id
  defp extract_script_id(other), do: inspect(other)
end
