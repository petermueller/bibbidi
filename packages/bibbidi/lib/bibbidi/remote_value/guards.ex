defmodule Bibbidi.RemoteValue.Guards do
  @moduledoc """
  Guards for the identity half of a `script.RemoteValue` map.

  `import Bibbidi.RemoteValue.Guards` to use them in function heads,
  `with` clauses and `case` branches:

      def handle_info(%Events.Script.Message{data: data}, state) when is_ref(data), do: ...

      case result do
        node when is_shared_id(node) -> click(conn, ctx, node)
        obj when is_handle(obj) -> ...
      end

  A value satisfies a guard only when the key is present *and* a string;
  `%{"handle" => nil}` does not count.
  """

  @doc "True when `value` is a map carrying a string `\"sharedId\"` (a DOM node)."
  defguard is_shared_id(value)
           when is_map(value) and is_map_key(value, "sharedId") and
                  is_binary(:erlang.map_get("sharedId", value))

  @doc "True when `value` is a map carrying a string `\"handle\"` (a root-owned object)."
  defguard is_handle(value)
           when is_map(value) and is_map_key(value, "handle") and
                  is_binary(:erlang.map_get("handle", value))

  @doc """
  True when `value` can be sent back to the browser as a reference, i.e.
  `is_shared_id/1` or `is_handle/1` holds.
  """
  defguard is_ref(value) when is_shared_id(value) or is_handle(value)
end
