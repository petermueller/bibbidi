defmodule Bibbidi.TelemetryTest do
  use ExUnit.Case, async: false

  alias Bibbidi.Connection
  alias Bibbidi.Commands.BrowsingContext

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: Bibbidi.MockTransport,
        transport_opts: [owner: self()]
      )

    ref = make_ref()
    test_pid = self()

    handler = fn event, measurements, metadata, _ ->
      send(test_pid, {ref, event, measurements, metadata})
    end

    %{conn: conn, ref: ref, handler: handler}
  end

  describe "[:bibbidi, :command, :start] and [:bibbidi, :command, :stop]" do
    test "emitted on successful execute/3", %{conn: conn, ref: ref, handler: handler} do
      id = "telemetry-ok-#{inspect(ref)}"

      :telemetry.attach_many(
        id,
        [[:bibbidi, :command, :start], [:bibbidi, :command, :stop]],
        handler,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)

      cmd = %BrowsingContext.Activate{context: "ctx-1"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      assert {:ok, _} = Task.await(task)

      assert_receive {^ref, [:bibbidi, :command, :start], %{system_time: _},
                      %{command: ^cmd, method: "browsingContext.activate", connection: ^conn}}

      assert_receive {^ref, [:bibbidi, :command, :stop], %{duration: duration},
                      %{result: {:ok, _}, command: ^cmd}}

      assert is_integer(duration) and duration >= 0
    end

    test "emitted with error result on command failure", %{conn: conn, ref: ref, handler: handler} do
      id = "telemetry-err-#{inspect(ref)}"

      :telemetry.attach_many(
        id,
        [[:bibbidi, :command, :start], [:bibbidi, :command, :stop]],
        handler,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)

      cmd = %BrowsingContext.Activate{context: "ctx-1"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)

      send(
        conn,
        {:mock_transport_receive,
         [{:text, JSON.encode!(%{id: decoded["id"], error: "oops", message: "fail"})}]}
      )

      assert {:error, _} = Task.await(task)

      assert_receive {^ref, [:bibbidi, :command, :start], _, _}
      assert_receive {^ref, [:bibbidi, :command, :stop], %{duration: _}, %{result: {:error, _}}}
    end
  end

  describe "[:bibbidi, :event, :received]" do
    test "emitted when a BiDi event arrives", %{conn: conn, ref: ref, handler: handler} do
      id = "telemetry-event-#{inspect(ref)}"

      :telemetry.attach_many(
        id,
        [[:bibbidi, :event, :received]],
        handler,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)

      # Subscribe to receive the event (so dispatch_event is called)
      Connection.subscribe(conn, "browsingContext.load")

      # Simulate a BiDi event from the browser
      event_json =
        JSON.encode!(%{
          method: "browsingContext.load",
          params: %{context: "ctx-1", url: "https://example.com", navigation: "nav-1"}
        })

      send(conn, {:mock_transport_receive, [{:text, event_json}]})

      # Verify the process message still works
      assert_receive {:bibbidi_event, "browsingContext.load", _params}

      # Verify telemetry was emitted
      assert_receive {^ref, [:bibbidi, :event, :received], %{system_time: _},
                      %{event: "browsingContext.load", params: _, connection: _}}
    end
  end
end
