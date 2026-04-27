defmodule Playbook.Recorder do
  @moduledoc """
  Records browser interactions by injecting JavaScript event listeners.

  Captures clicks, inputs, and navigations automatically while the user
  interacts with the browser. Uses Autopilot.Browser for browser access.

  ## Usage

      Playbook.Recorder.start_link()
      Playbook.Recorder.begin_session("Login Flow")

      # User interacts with the browser...
      # Events are captured automatically via injected JS

      Playbook.Recorder.annotate("this input is for 2FA")
      {:ok, name, log} = Playbook.Recorder.end_session()
  """

  use GenServer
  require Logger

  alias Playbook.LogEntry

  defp poll_interval_ms do
    Application.get_env(:playbook, :poll_interval_ms, 1_000)
  end

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

  @doc "Get the current log without stopping."
  def get_log do
    GenServer.call(__MODULE__, :get_log)
  end

  @doc "Check if currently recording."
  def recording? do
    GenServer.call(__MODULE__, :recording?)
  rescue
    _ -> false
  end

  # ── GenServer callbacks ────────────────────────────────────────

  @impl true
  def init(_state) do
    {:ok, %{
      recording: false,
      session_name: nil,
      log: [],
      last_poll_index: 0
    }}
  end

  @impl true
  def handle_call({:begin_session, name}, _from, state) do
    case inject_listeners() do
      :ok ->
        Logger.info("[Recorder] Started session: #{name}")
        schedule_poll()
        {:reply, :ok, %{state |
          recording: true,
          session_name: name,
          log: [],
          last_poll_index: 0
        }}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:annotate, text}, _from, %{recording: true} = state) do
    entry = LogEntry.annotation(text)
    Logger.info("[Recorder] #{LogEntry.to_log_line(entry)}")
    {:reply, :ok, %{state | log: state.log ++ [entry]}}
  end

  def handle_call({:annotate, _text}, _from, %{recording: false} = state) do
    {:reply, {:error, :not_recording}, state}
  end

  def handle_call(:end_session, _from, %{recording: true} = state) do
    state = poll_events(state)
    remove_listeners()

    Logger.info("[Recorder] Session ended: #{state.session_name} (#{length(state.log)} events)")
    log = state.log

    {:reply, {:ok, state.session_name, log}, %{state |
      recording: false,
      session_name: nil
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

  @impl true
  def handle_info(:poll, %{recording: true} = state) do
    state = poll_events(state)
    schedule_poll()
    {:noreply, state}
  end

  def handle_info(:poll, %{recording: false} = state) do
    {:noreply, state}
  end

  # ── JavaScript injection ───────────────────────────────────────

  defp inject_listeners do
    js = """
    (function() {
      if (window.__playbook_recorder) return 'already_injected';

      window.__playbook_events = [];
      window.__playbook_recorder = true;

      // Track clicks
      document.addEventListener('click', function(e) {
        var el = e.target;
        var selector = '';
        try {
          if (el.id) selector = '#' + el.id;
          else if (el.name) selector = el.tagName.toLowerCase() + '[name="' + el.name + '"]';
          else if (el.className && typeof el.className === 'string')
            selector = el.tagName.toLowerCase() + '.' + el.className.trim().split(/\\s+/).join('.');
          else selector = el.tagName.toLowerCase();
        } catch(err) { selector = el.tagName || 'unknown'; }

        window.__playbook_events.push({
          type: 'click',
          ts: Date.now(),
          x: Math.round(e.clientX),
          y: Math.round(e.clientY),
          selector: selector,
          tag: (el.tagName || '').toLowerCase(),
          text: (el.textContent || '').trim().slice(0, 80)
        });
      }, true);

      // Track input changes
      document.addEventListener('change', function(e) {
        var el = e.target;
        if (!el.tagName || !['INPUT','TEXTAREA','SELECT'].includes(el.tagName)) return;

        var selector = '';
        try {
          if (el.id) selector = '#' + el.id;
          else if (el.name) selector = el.tagName.toLowerCase() + '[name="' + el.name + '"]';
          else selector = el.tagName.toLowerCase();
        } catch(err) { selector = el.tagName || 'unknown'; }

        var sensitive = (el.type === 'password');

        window.__playbook_events.push({
          type: 'input',
          ts: Date.now(),
          selector: selector,
          value: sensitive ? '***' : el.value,
          sensitive: sensitive
        });
      }, true);

      // Track navigation via History API
      var origPush = history.pushState;
      var origReplace = history.replaceState;
      history.pushState = function() {
        origPush.apply(this, arguments);
        window.__playbook_events.push({
          type: 'navigation', ts: Date.now(), url: window.location.href, title: document.title
        });
      };
      history.replaceState = function() {
        origReplace.apply(this, arguments);
        window.__playbook_events.push({
          type: 'navigation', ts: Date.now(), url: window.location.href, title: document.title
        });
      };
      window.addEventListener('popstate', function() {
        window.__playbook_events.push({
          type: 'navigation', ts: Date.now(), url: window.location.href, title: document.title
        });
      });

      return 'injected';
    })()
    """

    case Autopilot.Browser.eval(js) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp remove_listeners do
    js = """
    (function() {
      window.__playbook_recorder = false;
      window.__playbook_events = [];
      return 'removed';
    })()
    """
    Autopilot.Browser.eval(js)
  end

  # ── Event polling ──────────────────────────────────────────────

  defp poll_events(state) do
    js = """
    (function() {
      var events = window.__playbook_events || [];
      var fromIndex = #{state.last_poll_index};
      var newEvents = events.slice(fromIndex);
      return JSON.stringify({count: events.length, events: newEvents});
    })()
    """

    case Autopilot.Browser.eval(js) do
      {:ok, json} when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, %{"count" => count, "events" => events}} ->
            entries = Enum.map(events, &parse_event/1)
            Enum.each(entries, fn e -> Logger.info("[Recorder] #{LogEntry.to_log_line(e)}") end)
            %{state | log: state.log ++ entries, last_poll_index: count}

          _ ->
            state
        end

      _ ->
        state
    end
  end

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

  # ── Helpers ────────────────────────────────────────────────────

  defp schedule_poll do
    Process.send_after(self(), :poll, poll_interval_ms())
  end
end
