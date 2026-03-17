defmodule Bibbidi.MockTransport do
  @moduledoc """
  Mock transport for testing the Connection GenServer without a real WebSocket.
  """

  @behaviour Bibbidi.Transport

  defstruct [:owner, :ref, messages: []]

  @impl true
  def connect(_uri, opts) do
    owner = Keyword.get(opts, :owner, self())
    {:ok, %__MODULE__{owner: owner, ref: make_ref()}}
  end

  @impl true
  def send_message(state, message) do
    send(state.owner, {:mock_transport_send, message})
    {:ok, state}
  end

  @impl true
  def handle_in(state, {:mock_transport_receive, frames}) do
    {:ok, state, frames}
  end

  def handle_in(_state, _message), do: :unknown

  @impl true
  def close(state) do
    send(state.owner, :mock_transport_closed)
    {:ok, state}
  end
end
