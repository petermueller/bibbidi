defmodule Bibbidi.Transport do
  @moduledoc """
  Behaviour for WebSocket transports.

  Messages from the remote end arrive as Erlang messages to the owning process.
  Implementations handle these in `c:handle_in/2`, returning decoded frames.
  """

  @type state :: term()

  @doc """
  Opens a WebSocket connection to the given URI.
  """
  @callback connect(uri :: URI.t(), opts :: keyword()) :: {:ok, state} | {:error, term()}

  @doc """
  Sends a text message over the WebSocket.
  """
  @callback send_message(state, message :: binary()) :: {:ok, state} | {:error, state, term()}

  @doc """
  Sends a pong frame in response to a ping.
  """
  @callback send_pong(state) :: {:ok, state} | {:error, state, term()}

  @doc """
  Handles an incoming Erlang message that may contain WebSocket data.

  Returns `{:ok, state, frames}` where frames is a list of decoded frames,
  or `:unknown` if the message is not relevant to this transport.
  """
  @callback handle_in(state, message :: term()) ::
              {:ok, state, [{:text, binary()} | :ping | :pong | {:close, integer(), binary()}]}
              | :unknown

  @doc """
  Closes the WebSocket connection.
  """
  @callback close(state) :: {:ok, state} | {:error, state, term()}
end
