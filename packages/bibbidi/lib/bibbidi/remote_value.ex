defmodule Bibbidi.RemoteValue do
  @moduledoc """
  Helpers for `script.RemoteValue` maps — the wire form of every JavaScript
  value the browser sends back (command results, `script.message` channel
  payloads, exception details).

  A RemoteValue has two halves:

    * **data** — the `"value"` key, a serialised snapshot
    * **identity** — a `"handle"` (realm-scoped, present only when the call
      asked for `result_ownership: "root"` / channel `ownership: "root"`) or,
      for DOM nodes, a `"sharedId"` (stable across realms)

  `to_term/1` converts the data half into plain Elixir terms. It is lossy by
  design: handles and shared ids are dropped, so keep the original map when
  you need to send the value back to the browser. `ref/1`, `handle/1` and
  `shared_id/1` read the identity half.

  ## Conversions performed by `to_term/1`

  | RemoteValue type                    | Elixir                                   |
  | ----------------------------------- | ---------------------------------------- |
  | `undefined`                         | `:undefined`                             |
  | `null`                              | `nil`                                    |
  | `string`, `boolean`, `number`       | the value                                |
  | `number` `"NaN"`                    | `:nan`                                   |
  | `number` `"Infinity"`/`"-Infinity"` | `:infinity` / `:neg_infinity`            |
  | `number` `"-0"`                     | `-0.0`                                   |
  | `bigint`                            | integer                                  |
  | `array`, `nodelist`, `htmlcollection` | list                                   |
  | `set`                               | `MapSet`                                 |
  | `object`, `map`                     | map (keys converted too)                 |
  | `date`                              | `DateTime` (ISO 8601 string on failure)  |
  | `regexp`                            | `%{"pattern" => _, "flags" => _}`        |
  | anything else                       | the map, unchanged                       |

  "Anything else" covers `node` and `window` (reference types — flattening a
  node would discard the `sharedId` that makes it useful), values with no
  serialisation (`function`, `symbol`, `promise`, `error`, `weakmap`,
  `weakset`, `generator`, `proxy`, `typedarray`, `arraybuffer`), values
  truncated by `max_object_depth`, and the back-references BiDi emits for
  cyclic structures (`"internalId"` without `"value"`). Returning the raw map
  rather than `nil` keeps any handle reachable.
  """

  @typedoc "A `script.RemoteValue` map as decoded from the wire."
  @type t :: %{required(String.t()) => term()}

  @typedoc """
  A reference the browser accepts in place of a value: `script.SharedReference`
  for nodes, `script.RemoteObjectReference` otherwise.
  """
  @type reference_map :: %{String.t() => String.t()}

  @doc """
  Converts a RemoteValue's data into an Elixir term. See the module doc for the
  conversion table. Identity (`"handle"`, `"sharedId"`) is dropped.

      iex> Bibbidi.RemoteValue.to_term(%{"type" => "object", "value" => [["n", %{"type" => "number", "value" => 1}]]})
      %{"n" => 1}
  """
  @spec to_term(t()) :: term()
  def to_term(%{"type" => "undefined"}), do: :undefined
  def to_term(%{"type" => "null"}), do: nil
  def to_term(%{"type" => "string", "value" => value}), do: value
  def to_term(%{"type" => "boolean", "value" => value}), do: value
  def to_term(%{"type" => "number", "value" => "NaN"}), do: :nan
  def to_term(%{"type" => "number", "value" => "Infinity"}), do: :infinity
  def to_term(%{"type" => "number", "value" => "-Infinity"}), do: :neg_infinity
  def to_term(%{"type" => "number", "value" => "-0"}), do: -0.0
  def to_term(%{"type" => "number", "value" => value}) when is_number(value), do: value
  def to_term(%{"type" => "bigint", "value" => value}), do: String.to_integer(value)

  def to_term(%{"type" => type, "value" => items})
      when type in ["array", "nodelist", "htmlcollection"],
      do: Enum.map(items, &to_term/1)

  def to_term(%{"type" => "set", "value" => items}), do: MapSet.new(items, &to_term/1)

  def to_term(%{"type" => type, "value" => pairs}) when type in ["object", "map"],
    do: Map.new(pairs, fn [key, value] -> {key_to_term(key), to_term(value)} end)

  def to_term(%{"type" => "date", "value" => iso8601}) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> iso8601
    end
  end

  def to_term(%{"type" => "regexp", "value" => value}), do: value
  def to_term(%{"type" => _} = raw), do: raw

  # Object keys are plain text; Map keys may be any RemoteValue.
  defp key_to_term(key) when is_binary(key), do: key
  defp key_to_term(%{"type" => _} = key), do: to_term(key)

  @doc """
  Returns the reference the browser accepts in place of this value — as a
  `script.callFunction` argument or `this`, or as an `input.performActions`
  pointer origin element — or `nil` when the value carries no identity.

  Prefers `"sharedId"` (nodes; valid across realms) over `"handle"`.

      iex> Bibbidi.RemoteValue.ref(%{"type" => "node", "sharedId" => "n1", "value" => %{}})
      %{"sharedId" => "n1"}
      iex> Bibbidi.RemoteValue.ref(%{"type" => "object", "handle" => "h1"})
      %{"handle" => "h1"}
      iex> Bibbidi.RemoteValue.ref(%{"type" => "object", "value" => []})
      nil

  A `nil` from a value you expected to reference usually means the call that
  produced it did not ask for `result_ownership: "root"`.
  """
  @spec ref(t()) :: reference_map() | nil
  def ref(%{"sharedId" => shared_id}) when is_binary(shared_id), do: %{"sharedId" => shared_id}
  def ref(%{"handle" => handle}) when is_binary(handle), do: %{"handle" => handle}
  def ref(%{}), do: nil

  @doc """
  Returns the bare `script.Handle` string, or `nil`.

  This is the form `script.disown` takes (`handles: [handle]`); everywhere
  else the browser wants the map form from `ref/1`.
  """
  @spec handle(t()) :: String.t() | nil
  def handle(%{"handle" => handle}) when is_binary(handle), do: handle
  def handle(%{}), do: nil

  @doc "Returns the bare `script.SharedId` string of a node value, or `nil`."
  @spec shared_id(t()) :: String.t() | nil
  def shared_id(%{"sharedId" => shared_id}) when is_binary(shared_id), do: shared_id
  def shared_id(%{}), do: nil
end
