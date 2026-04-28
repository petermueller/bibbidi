defmodule Playbook.LogEntry do
  @moduledoc """
  A single recorded event from a browser session.

  Types:
    - navigation: page URL changed
    - click:      user clicked an element
    - input:      user typed into a field
    - pick:       user explicitly selected an element via overlay
    - annotation: free-text note from the user (context for the transformer)
  """

  @type entry_type :: :navigation | :click | :input | :pick | :annotation

  @type t :: %__MODULE__{
    timestamp: integer(),
    type: entry_type(),
    data: map()
  }

  @enforce_keys [:type, :data]
  defstruct [
    :timestamp,
    :type,
    :data
  ]

  @doc "Create a navigation entry."
  def navigation(url, title \\ nil) do
    %__MODULE__{
      timestamp: now(),
      type: :navigation,
      data: %{url: url, title: title}
    }
  end

  @doc "Create a click entry."
  def click(x, y, selector, tag, text) do
    %__MODULE__{
      timestamp: now(),
      type: :click,
      data: %{x: x, y: y, selector: selector, tag: tag, text: text}
    }
  end

  @doc "Create an input entry."
  def input(selector, value, sensitive \\ false) do
    %__MODULE__{
      timestamp: now(),
      type: :input,
      data: %{selector: selector, value: value, sensitive: sensitive}
    }
  end

  @doc "Create a pick entry (explicit element selection)."
  def pick(selector, tag, text, x, y) do
    %__MODULE__{
      timestamp: now(),
      type: :pick,
      data: %{selector: selector, tag: tag, text: text, x: x, y: y}
    }
  end

  @doc "Create a free-text annotation."
  def annotation(text) do
    %__MODULE__{
      timestamp: now(),
      type: :annotation,
      data: %{text: text}
    }
  end

  @doc "Serialize entry to a map for JSON encoding."
  def to_map(%__MODULE__{} = entry) do
    %{
      ts: entry.timestamp,
      type: Atom.to_string(entry.type),
      data: entry.data
    }
  end

  @doc "Serialize a list of entries to a JSON string."
  def to_json(entries) when is_list(entries) do
    entries
    |> Enum.map(&to_map/1)
    |> Jason.encode!(pretty: true)
  end

  @doc "Format entry as a human-readable log line for the transformer."
  def to_log_line(%__MODULE__{} = entry) do
    case entry.type do
      :navigation ->
        "[NAV] #{entry.data.url}"

      :click ->
        text = if entry.data.text && entry.data.text != "", do: " \"#{entry.data.text}\"", else: ""
        "[CLICK] (#{entry.data.x}, #{entry.data.y}) <#{entry.data.tag}> #{entry.data.selector}#{text}"

      :input ->
        value = if entry.data.sensitive, do: "***", else: entry.data.value
        "[INPUT] #{entry.data.selector} = \"#{value}\""

      :pick ->
        text = if entry.data.text && entry.data.text != "", do: " \"#{entry.data.text}\"", else: ""
        "[PICK] <#{entry.data.tag}> #{entry.data.selector}#{text} at (#{entry.data.x}, #{entry.data.y})"

      :annotation ->
        "[NOTE] #{entry.data.text}"
    end
  end


  @doc """
    Build a LogEntry struct from a raw map (the JSON-decoded form from .jsonl files).
    Returns the struct, or nil for unrecognized types.
    """
  def from_raw_map(%{"type" => "navigation"} = e),
    do: navigation(e["url"], e["title"])

  def from_raw_map(%{"type" => "click"} = e),
    do: click(e["x"], e["y"], e["selector"], e["tag"], e["text"])

  def from_raw_map(%{"type" => "input"} = e),
    do: input(e["selector"], e["value"], e["sensitive"] || false)

  def from_raw_map(%{"type" => "pick"} = e),
    do: pick(e["selector"], e["tag"], e["text"], e["x"], e["y"])

  def from_raw_map(%{"type" => "annotation"} = e),
    do: annotation(e["text"])

  def from_raw_map(_), do: nil


  defp now, do: System.system_time(:millisecond)
end
