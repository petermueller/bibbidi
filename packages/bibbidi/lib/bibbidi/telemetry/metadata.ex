defprotocol Bibbidi.Telemetry.Metadata do
  @moduledoc """
  Protocol for extracting correlation metadata from command and event structs.

  Used by `Bibbidi.Connection` to enrich telemetry events with correlation
  data (e.g., `:meta`, `:context`, `:navigation`, `:request`).

  ## Deriving

  Command structs derive with no options to extract `%{meta: struct.meta}`:

      @derive Bibbidi.Telemetry.Metadata
      defstruct [:url, :context, :meta]

  Event structs derive with explicit keys:

      @derive {Bibbidi.Telemetry.Metadata, keys: [:context, :navigation]}
      defstruct [:method, :context, :navigation, :url]

  The `Any` fallback returns `%{}` for non-derived structs and non-structs.
  """

  @fallback_to_any true

  @doc "Extracts correlation metadata from the given struct."
  @spec telemetry_metadata(t()) :: map()
  def telemetry_metadata(value)
end

defimpl Bibbidi.Telemetry.Metadata, for: Any do
  defmacro __deriving__(module, _struct, opts) do
    keys = Keyword.get(opts, :keys, [:meta])

    quote do
      defimpl Bibbidi.Telemetry.Metadata, for: unquote(module) do
        def telemetry_metadata(struct) do
          Map.take(struct, unquote(keys))
        end
      end
    end
  end

  def telemetry_metadata(_), do: %{}
end
