defmodule Bibbidi.CommandMetaTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.BrowsingContext.Navigate
  alias Bibbidi.Commands.BrowsingContext.Activate

  describe ":meta field" do
    test "defaults to nil" do
      cmd = %Activate{context: "ctx-1"}
      assert cmd.meta == nil
    end

    test "can be set to arbitrary data" do
      cmd = %Navigate{context: "ctx-1", url: "https://example.com", meta: %{trace_id: "abc"}}
      assert cmd.meta == %{trace_id: "abc"}
    end

    test "is excluded from Encodable.params/1" do
      cmd = %Navigate{context: "ctx-1", url: "https://example.com", meta: %{trace_id: "abc"}}
      params = Bibbidi.Encodable.params(cmd)

      refute Map.has_key?(params, :meta)
      assert params == %{context: "ctx-1", url: "https://example.com"}
    end

    test "is excluded from params even for commands with no optional fields" do
      cmd = %Activate{context: "ctx-1", meta: %{id: 1}}
      params = Bibbidi.Encodable.params(cmd)

      refute Map.has_key?(params, :meta)
      assert params == %{context: "ctx-1"}
    end
  end
end

defmodule Bibbidi.CommandMetaTelemetryTest do
  use ExUnit.Case, async: false

  alias Bibbidi.Commands.BrowsingContext.Navigate

  setup do
    {:ok, conn} =
      Bibbidi.Connection.start_link(
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

  test ":meta is included in command telemetry", %{conn: conn, ref: ref, handler: handler} do
    id = "meta-telemetry-#{inspect(ref)}"

    :telemetry.attach_many(
      id,
      [[:bibbidi, :command, :start], [:bibbidi, :command, :stop]],
      handler,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    cmd = %Navigate{context: "ctx-1", url: "https://example.com", meta: %{trace_id: "t1"}}
    task = Task.async(fn -> Bibbidi.Connection.execute(conn, cmd) end)

    assert_receive {:mock_transport_send, json}
    decoded = JSON.decode!(json)

    send(
      conn,
      {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
    )

    Task.await(task)

    assert_receive {^ref, [:bibbidi, :command, :start], _, metadata}
    assert metadata.meta == %{trace_id: "t1"}
  end

  test "event telemetry includes correlation keys", %{conn: conn, ref: ref, handler: handler} do
    id = "event-correlation-#{inspect(ref)}"

    :telemetry.attach(id, [:bibbidi, :event, :received], handler, nil)
    on_exit(fn -> :telemetry.detach(id) end)

    Bibbidi.Connection.subscribe(conn, "browsingContext.load")

    event_json =
      JSON.encode!(%{
        method: "browsingContext.load",
        params: %{context: "ctx-1", url: "https://example.com", navigation: "nav-1"}
      })

    send(conn, {:mock_transport_receive, [{:text, event_json}]})

    assert_receive {^ref, [:bibbidi, :event, :received], _, metadata}
    assert metadata.context == "ctx-1"
    assert metadata.navigation == "nav-1"
  end

  test "unknown event telemetry has no correlation keys", %{
    conn: conn,
    ref: ref,
    handler: handler
  } do
    id = "unknown-event-#{inspect(ref)}"

    :telemetry.attach(id, [:bibbidi, :event, :received], handler, nil)
    on_exit(fn -> :telemetry.detach(id) end)

    Bibbidi.Connection.subscribe(conn, "vendor.custom")

    event_json =
      JSON.encode!(%{
        method: "vendor.custom",
        params: %{foo: "bar"}
      })

    send(conn, {:mock_transport_receive, [{:text, event_json}]})

    assert_receive {^ref, [:bibbidi, :event, :received], _, metadata}
    assert metadata.params == %{"foo" => "bar"}
    refute Map.has_key?(metadata, :context)
  end
end
