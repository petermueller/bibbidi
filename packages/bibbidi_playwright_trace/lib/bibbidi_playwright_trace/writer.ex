defmodule BibbidiPlaywrightTrace.Writer do
  @moduledoc """
  Writes a Playwright-compatible trace zip file from collected trace events.

  The zip contains:
  - `trace.trace` — NDJSON of trace events
  - `trace.network` — NDJSON of network events (empty if none)
  - `resources/{sha1}` — binary blobs (screenshots, etc.) keyed by SHA1 hash
  """

  @doc """
  Writes a trace zip file to `path`.

  `trace_events` is an ordered list of maps, each representing a Playwright trace event.
  The first event should be a `"context-options"` event.

  `resources` is a map of `%{sha1_string => binary_data}` for screenshot data, etc.
  """
  @spec write_zip(Path.t(), [map()], %{String.t() => binary()}) ::
          :ok | {:error, term()}
  def write_zip(path, trace_events, resources \\ %{}) do
    trace_ndjson = encode_ndjson(trace_events)
    network_ndjson = ""

    entries =
      [
        {~c"trace.trace", trace_ndjson},
        {~c"trace.network", network_ndjson}
      ] ++
        Enum.map(resources, fn {sha1, data} ->
          {String.to_charlist("resources/#{sha1}"), data}
        end)

    case :zip.create(String.to_charlist(path), entries, [:memory]) do
      {:ok, {_name, zip_binary}} ->
        File.write(path, zip_binary)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds the context-options event that must be the first line in `trace.trace`.
  """
  @spec context_options(keyword()) :: map()
  def context_options(opts \\ []) do
    browser_name = Keyword.get(opts, :browser_name, "unknown")
    platform = Keyword.get(opts, :platform, to_string(:os.type() |> elem(1)))

    options =
      case Keyword.get(opts, :viewport) do
        nil -> %{}
        %{width: w, height: h} -> %{"viewport" => %{"width" => w, "height" => h}}
        {w, h} -> %{"viewport" => %{"width" => w, "height" => h}}
      end

    %{
      "type" => "context-options",
      "browserName" => browser_name,
      "platform" => platform,
      "wallTime" => System.system_time(:millisecond),
      "monotonicTime" => System.monotonic_time(:millisecond),
      "origin" => "library",
      "options" => options
    }
  end

  @doc """
  Builds a `before` trace event for a command about to be sent.
  """
  @spec before_event(String.t(), number(), String.t(), map()) :: map()
  def before_event(call_id, start_time, method, params) do
    {class, method_name} = split_method(method)

    %{
      "type" => "before",
      "callId" => call_id,
      "startTime" => start_time,
      "class" => class,
      "method" => method_name,
      "params" => params
    }
  end

  @doc """
  Builds an `after` trace event for a completed command.
  """
  @spec after_event(String.t(), number(), {:ok, term()} | {:error, term()}) :: map()
  def after_event(call_id, end_time, result) do
    base = %{
      "type" => "after",
      "callId" => call_id,
      "endTime" => end_time
    }

    case result do
      {:ok, response} ->
        Map.put(base, "result", response)

      {:error, reason} ->
        Map.put(base, "error", %{"message" => inspect(reason)})
    end
  end

  @doc """
  Builds a BiDi event trace entry.
  """
  @spec bidi_event(number(), String.t(), map()) :: map()
  def bidi_event(time, event_name, params) do
    {class, method_name} = split_method(event_name)

    %{
      "type" => "event",
      "time" => time,
      "class" => class,
      "method" => method_name,
      "params" => params
    }
  end

  @doc """
  Builds a screencast-frame trace event for a captured screenshot.

  Returns `{event, sha1, binary}` where `sha1` is the resource key and `binary`
  is the decoded screenshot data.
  """
  @spec screencast_frame(String.t(), number(), String.t(), keyword()) ::
          {map(), String.t(), binary()}
  def screencast_frame(page_id, timestamp, base64_data, opts \\ []) do
    binary = Base.decode64!(base64_data)
    sha1 = :crypto.hash(:sha, binary) |> Base.encode16(case: :lower)
    width = Keyword.get(opts, :width, 0)
    height = Keyword.get(opts, :height, 0)

    event = %{
      "type" => "screencast-frame",
      "pageId" => page_id,
      "sha1" => sha1,
      "width" => width,
      "height" => height,
      "timestamp" => timestamp
    }

    {event, sha1, binary}
  end

  defp encode_ndjson(events) do
    events
    |> Enum.map_join("\n", &Jason.encode!/1)
    |> then(fn
      "" -> ""
      data -> data <> "\n"
    end)
  end

  defp split_method(method) do
    case String.split(method, ".", parts: 2) do
      [class, name] -> {class, name}
      [name] -> {"bibbidi", name}
    end
  end
end
