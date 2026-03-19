defmodule BibbidiPlaywrightTrace do
  @moduledoc """
  Generates Playwright-compatible trace zip files from Bibbidi telemetry events.

  Attaches to Bibbidi's telemetry events (`[:bibbidi, :command, :start]`,
  `[:bibbidi, :command, :stop]`, `[:bibbidi, :event, :received]`) to collect
  command and event data, then writes a `trace.zip` viewable at
  [trace.playwright.dev](https://trace.playwright.dev).

  ## Usage

      # Start collecting trace data
      {:ok, collector} = BibbidiPlaywrightTrace.start(browser_name: "firefox")

      # ... run bibbidi commands via Connection.execute/2 ...

      # Stop and write the trace
      :ok = BibbidiPlaywrightTrace.stop(collector, "trace.zip")

  ## Options

  - `:browser_name` — browser name for the trace header (default: `"unknown"`)
  - `:platform` — platform string (default: detected from OS)
  - `:viewport` — `{width, height}` tuple or `%{width: w, height: h}` map
  - `:connection` — only trace commands sent to this connection pid
  - `:reducer` — MFA or MFArgs for custom event transformation

  ## Reducer

  The reducer lets you customize how BiDi commands appear in the trace.
  It's called for each completed command (before/after pair):

      # MFA — called as MyModule.reduce(before_event, after_event)
      BibbidiPlaywrightTrace.start(reducer: {MyModule, :reduce, 2})

      # MFArgs — called as MyModule.reduce(before_event, after_event, some: :opt)
      BibbidiPlaywrightTrace.start(reducer: {MyModule, :reduce, [some: :opt]})

  The reducer must return one of:
  - `{before_event, after_event}` — possibly modified events
  - `[{before, after}, ...]` — split one command into multiple trace actions
  - `:skip` — omit this command from the trace

  Without a reducer, every `Connection.execute/2` call produces one
  before/after pair using the BiDi method name directly.
  """

  alias BibbidiPlaywrightTrace.{Collector, Writer}

  @doc """
  Starts a trace collector that listens to Bibbidi telemetry events.

  Returns `{:ok, collector_pid}`.
  """
  @spec start(keyword()) :: {:ok, pid()}
  def start(opts \\ []) do
    Collector.start_link(opts)
  end

  @doc """
  Stops the collector and writes the trace zip to `path`.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec stop(GenServer.server(), Path.t()) :: :ok | {:error, term()}
  def stop(collector, path) do
    {events, resources} = Collector.stop(collector)
    Writer.write_zip(path, events, resources)
  end

  @doc """
  Returns the accumulated trace data without stopping the collector.

  Returns `{trace_events, resources}`.
  """
  @spec peek(GenServer.server()) :: {[map()], %{String.t() => binary()}}
  def peek(collector) do
    Collector.get_trace(collector)
  end
end
