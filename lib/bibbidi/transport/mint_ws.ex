defmodule Bibbidi.Transport.MintWS do
  @moduledoc """
  WebSocket transport implementation using `Mint.WebSocket`.
  """

  @behaviour Bibbidi.Transport

  defstruct [:conn, :websocket, :ref]

  @impl true
  def connect(%URI{} = uri, opts \\ []) do
    scheme = ws_to_http_scheme(uri.scheme)
    port = uri.port || default_port(uri.scheme)
    path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

    mint_opts = Keyword.get(opts, :mint_opts, [])
    ws_opts = Keyword.get(opts, :ws_opts, [])

    with {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, port, mint_opts),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(ws_scheme(uri.scheme), conn, path, [], ws_opts) do
      await_upgrade(conn, ref)
    end
  end

  @impl true
  def send_message(%__MODULE__{} = state, message) when is_binary(message) do
    case Mint.WebSocket.encode(state.websocket, {:text, message}) do
      {:ok, websocket, data} ->
        case Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
          {:ok, conn} -> {:ok, %{state | conn: conn, websocket: websocket}}
          {:error, conn, reason} -> {:error, %{state | conn: conn}, reason}
        end

      {:error, websocket, reason} ->
        {:error, %{state | websocket: websocket}, reason}
    end
  end

  @impl true
  def handle_in(%__MODULE__{} = state, message) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn}
        decode_responses(state, responses, [])

      :unknown ->
        :unknown

      {:error, conn, reason, _responses} ->
        {:ok, %{state | conn: conn}, [{:error, reason}]}
    end
  end

  @impl true
  def close(%__MODULE__{} = state) do
    case Mint.WebSocket.encode(state.websocket, :close) do
      {:ok, websocket, data} ->
        case Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
          {:ok, conn} ->
            Mint.HTTP.close(conn)
            {:ok, %{state | conn: conn, websocket: websocket}}

          {:error, conn, reason} ->
            Mint.HTTP.close(conn)
            {:error, %{state | conn: conn}, reason}
        end

      {:error, websocket, reason} ->
        Mint.HTTP.close(state.conn)
        {:error, %{state | websocket: websocket}, reason}
    end
  end

  ## Private

  defp await_upgrade(conn, ref) do
    await_upgrade(conn, ref, [])
  end

  defp await_upgrade(conn, ref, acc) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            acc = acc ++ responses
            complete_upgrade(conn, ref, acc)

          {:error, conn, reason, _responses} ->
            Mint.HTTP.close(conn)
            {:error, reason}

          :unknown ->
            Mint.HTTP.close(conn)
            {:error, :unexpected_message}
        end
    after
      10_000 ->
        Mint.HTTP.close(conn)
        {:error, :upgrade_timeout}
    end
  end

  defp complete_upgrade(conn, ref, responses) do
    status =
      Enum.find_value(responses, fn
        {:status, ^ref, s} -> s
        _ -> nil
      end)

    headers =
      Enum.find_value(responses, fn
        {:headers, ^ref, h} -> h
        _ -> nil
      end)

    done? = Enum.any?(responses, &match?({:done, ^ref}, &1))

    cond do
      status && headers && done? ->
        case Mint.WebSocket.new(conn, ref, status, headers) do
          {:ok, conn, websocket} ->
            {:ok, %__MODULE__{conn: conn, websocket: websocket, ref: ref}}

          {:error, conn, reason} ->
            Mint.HTTP.close(conn)
            {:error, reason}
        end

      true ->
        # Still waiting for more response parts
        await_upgrade(conn, ref, responses)
    end
  end

  defp decode_responses(state, [], acc) do
    {:ok, state, Enum.reverse(acc)}
  end

  defp decode_responses(state, [{:data, ref, data} | rest], acc) when ref == state.ref do
    case Mint.WebSocket.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        state = %{state | websocket: websocket}
        acc = Enum.reduce(frames, acc, &[normalize_frame(&1) | &2])
        decode_responses(state, rest, acc)

      {:error, websocket, reason} ->
        {:ok, %{state | websocket: websocket}, Enum.reverse([{:error, reason} | acc])}
    end
  end

  defp decode_responses(state, [_other | rest], acc) do
    decode_responses(state, rest, acc)
  end

  defp normalize_frame({:text, data}), do: {:text, data}
  defp normalize_frame({:ping, _}), do: :ping
  defp normalize_frame({:pong, _}), do: :pong
  defp normalize_frame({:close, code, reason}), do: {:close, code, reason}
  defp normalize_frame(other), do: other

  defp ws_to_http_scheme("ws"), do: :http
  defp ws_to_http_scheme("wss"), do: :https
  defp ws_to_http_scheme(nil), do: :http

  defp ws_scheme("ws"), do: :ws
  defp ws_scheme("wss"), do: :wss
  defp ws_scheme(nil), do: :ws

  defp default_port("ws"), do: 80
  defp default_port("wss"), do: 443
  defp default_port(nil), do: 80
end
