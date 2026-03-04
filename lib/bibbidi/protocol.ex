defmodule Bibbidi.Protocol do
  @moduledoc """
  Pure encoding and decoding of WebDriver BiDi protocol messages.

  All functions are stateless — no process state involved.
  """

  @doc """
  Encodes a command into a JSON binary.
  """
  @spec encode_command(id :: non_neg_integer(), method :: String.t(), params :: map()) :: binary()
  def encode_command(id, method, params) do
    JSON.encode!(%{id: id, method: method, params: params})
  end

  @doc """
  Decodes a JSON message from the WebDriver BiDi server.

  Returns one of:
  - `{:command_response, id, result}` — successful response to a command
  - `{:error_response, id, error}` — error response to a command
  - `{:event, method, params}` — server-initiated event
  """
  @spec decode_message(binary()) ::
          {:command_response, non_neg_integer(), map()}
          | {:error_response, non_neg_integer(), map()}
          | {:event, String.t(), map()}
          | {:error, term()}
  def decode_message(json) do
    case JSON.decode(json) do
      {:ok, decoded} -> classify(decoded)
      {:error, reason} -> {:error, {:json_decode, reason}}
    end
  end

  defp classify(%{"id" => id, "result" => result}) do
    {:command_response, id, result}
  end

  defp classify(%{"id" => id, "error" => error} = msg) do
    {:error_response, id,
     %{error: error, message: msg["message"] || "", stacktrace: msg["stacktrace"]}}
  end

  defp classify(%{"method" => method, "params" => params}) do
    {:event, method, params}
  end

  defp classify(other) do
    {:error, {:unknown_message, other}}
  end
end
