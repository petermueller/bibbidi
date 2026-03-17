defmodule BibbidiPlaywrightTrace.CollectorTest do
  use ExUnit.Case, async: true

  alias BibbidiPlaywrightTrace.Collector
  alias Bibbidi.Connection

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: Bibbidi.MockTransport,
        transport_opts: [owner: self()]
      )

    %{conn: conn}
  end

  defp reply(conn, id, result \\ %{}) do
    send(conn, {:mock_transport_receive, [{:text, Jason.encode!(%{id: id, result: result})}]})
  end

  defp reply_error(conn, id, error \\ "fail") do
    send(
      conn,
      {:mock_transport_receive, [{:text, Jason.encode!(%{id: id, error: error, message: "failed"})}]}
    )
  end

  describe "basic collection" do
    test "collects before/after pairs from telemetry", %{conn: conn} do
      {:ok, collector} = Collector.start_link(browser_name: "firefox", connection: conn)

      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)

      assert_receive {:mock_transport_send, json}
      decoded = Jason.decode!(json)
      reply(conn, decoded["id"], %{"navigation" => "nav-1"})

      assert {:ok, _} = Task.await(task)
      Process.sleep(50)

      {events, _resources} = Collector.get_trace(collector)

      assert [context_opts | rest] = events
      assert context_opts["type"] == "context-options"
      assert context_opts["browserName"] == "firefox"

      before_evt = Enum.find(rest, &(&1["type"] == "before"))
      after_evt = Enum.find(rest, &(&1["type"] == "after"))

      assert before_evt["callId"] == "call@1"
      assert before_evt["class"] == "browsingContext"
      assert before_evt["method"] == "navigate"
      assert before_evt["params"]["url"] == "https://example.com"

      assert after_evt["callId"] == "call@1"
      assert after_evt["result"] == %{"navigation" => "nav-1"}

      GenServer.stop(collector)
    end

    test "collects error results", %{conn: conn} do
      {:ok, collector} = Collector.start_link(connection: conn)

      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)

      assert_receive {:mock_transport_send, json}
      decoded = Jason.decode!(json)
      reply_error(conn, decoded["id"])

      assert {:error, _} = Task.await(task)
      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)

      after_evt = Enum.find(events, &(&1["type"] == "after"))
      assert after_evt["error"]["message"] != nil

      GenServer.stop(collector)
    end

    test "assigns incrementing callIds", %{conn: conn} do
      {:ok, collector} = Collector.start_link(connection: conn)

      cmd1 = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://one.com"}
      task1 = Task.async(fn -> Connection.execute(conn, cmd1) end)
      assert_receive {:mock_transport_send, json1}
      decoded1 = Jason.decode!(json1)
      reply(conn, decoded1["id"])
      Task.await(task1)

      cmd2 = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://two.com"}
      task2 = Task.async(fn -> Connection.execute(conn, cmd2) end)
      assert_receive {:mock_transport_send, json2}
      decoded2 = Jason.decode!(json2)
      reply(conn, decoded2["id"])
      Task.await(task2)

      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)

      before_events =
        events
        |> Enum.filter(&(&1["type"] == "before"))
        |> Enum.map(& &1["callId"])

      assert before_events == ["call@1", "call@2"]

      GenServer.stop(collector)
    end
  end

  describe "connection filtering" do
    test "filters events by connection pid", %{conn: conn} do
      {:ok, other_conn} =
        Connection.start_link(
          url: "ws://localhost:5678",
          transport: Bibbidi.MockTransport,
          transport_opts: [owner: self()]
        )

      {:ok, collector} = Collector.start_link(connection: conn)

      # Command on the tracked connection
      cmd1 = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://tracked.com"}
      task1 = Task.async(fn -> Connection.execute(conn, cmd1) end)
      assert_receive {:mock_transport_send, json1}
      decoded1 = Jason.decode!(json1)
      reply(conn, decoded1["id"])
      Task.await(task1)

      # Command on a different connection (should be filtered out)
      cmd2 = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-2", url: "https://other.com"}
      task2 = Task.async(fn -> Connection.execute(other_conn, cmd2) end)
      assert_receive {:mock_transport_send, json2}
      decoded2 = Jason.decode!(json2)
      reply(other_conn, decoded2["id"])
      Task.await(task2)

      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)
      before_events = Enum.filter(events, &(&1["type"] == "before"))

      assert length(before_events) == 1
      assert hd(before_events)["params"]["url"] == "https://tracked.com"

      GenServer.stop(collector)
      GenServer.stop(other_conn)
    end
  end

  describe "BiDi event collection" do
    test "collects BiDi events as trace event entries", %{conn: conn} do
      {:ok, collector} = Collector.start_link(connection: conn)

      Connection.subscribe(conn, "browsingContext.load")

      event_json =
        Jason.encode!(%{
          method: "browsingContext.load",
          params: %{context: "ctx-1", url: "https://example.com"}
        })

      send(conn, {:mock_transport_receive, [{:text, event_json}]})
      assert_receive {:bibbidi_event, "browsingContext.load", _}

      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)
      bidi_events = Enum.filter(events, &(&1["type"] == "event"))

      assert length(bidi_events) == 1
      assert hd(bidi_events)["class"] == "browsingContext"
      assert hd(bidi_events)["method"] == "load"

      GenServer.stop(collector)
    end
  end

  describe "reducer" do
    defmodule TestReducer do
      def rename(before_evt, after_evt) do
        before_evt = %{before_evt | "class" => "page", "method" => "goto"}
        {before_evt, after_evt}
      end

      def skip(_before_evt, _after_evt) do
        :skip
      end

      def expand(before_evt, after_evt) do
        parent_id = before_evt["callId"]

        child_before =
          before_evt
          |> Map.put("callId", "#{parent_id}-sub")
          |> Map.put("parentId", parent_id)

        child_after = Map.put(after_evt, "callId", "#{parent_id}-sub")

        [{before_evt, after_evt}, {child_before, child_after}]
      end

      def with_opts(before_evt, after_evt, opts) do
        prefix = Keyword.get(opts, :prefix, "custom")
        before_evt = %{before_evt | "class" => prefix}
        {before_evt, after_evt}
      end
    end

    test "MFA reducer can rename events", %{conn: conn} do
      {:ok, collector} = Collector.start_link(reducer: {TestReducer, :rename, 2}, connection: conn)

      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)
      assert_receive {:mock_transport_send, json}
      reply(conn, Jason.decode!(json)["id"])
      Task.await(task)

      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)
      before_evt = Enum.find(events, &(&1["type"] == "before"))

      assert before_evt["class"] == "page"
      assert before_evt["method"] == "goto"

      GenServer.stop(collector)
    end

    test "reducer can skip events", %{conn: conn} do
      {:ok, collector} = Collector.start_link(reducer: {TestReducer, :skip, 2}, connection: conn)

      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)
      assert_receive {:mock_transport_send, json}
      reply(conn, Jason.decode!(json)["id"])
      Task.await(task)

      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)
      # Only context-options, no before/after
      assert length(events) == 1
      assert hd(events)["type"] == "context-options"

      GenServer.stop(collector)
    end

    test "reducer can expand into multiple events", %{conn: conn} do
      {:ok, collector} = Collector.start_link(reducer: {TestReducer, :expand, 2}, connection: conn)

      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)
      assert_receive {:mock_transport_send, json}
      reply(conn, Jason.decode!(json)["id"])
      Task.await(task)

      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)
      before_events = Enum.filter(events, &(&1["type"] == "before"))

      assert length(before_events) == 2
      assert Enum.at(before_events, 0)["callId"] == "call@1"
      assert Enum.at(before_events, 1)["callId"] == "call@1-sub"
      assert Enum.at(before_events, 1)["parentId"] == "call@1"

      GenServer.stop(collector)
    end

    test "MFArgs reducer receives extra args", %{conn: conn} do
      {:ok, collector} =
        Collector.start_link(
          reducer: {TestReducer, :with_opts, [prefix: "myapp"]},
          connection: conn
        )

      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)
      assert_receive {:mock_transport_send, json}
      reply(conn, Jason.decode!(json)["id"])
      Task.await(task)

      Process.sleep(50)

      {events, _} = Collector.get_trace(collector)
      before_evt = Enum.find(events, &(&1["type"] == "before"))

      assert before_evt["class"] == "myapp"

      GenServer.stop(collector)
    end
  end

  describe "stop/1" do
    test "returns trace data and stops the collector", %{conn: conn} do
      {:ok, collector} = Collector.start_link(connection: conn)

      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
      task = Task.async(fn -> Connection.execute(conn, cmd) end)
      assert_receive {:mock_transport_send, json}
      reply(conn, Jason.decode!(json)["id"])
      Task.await(task)

      Process.sleep(50)

      {events, resources} = Collector.stop(collector)

      assert is_list(events)
      assert is_map(resources)
      assert hd(events)["type"] == "context-options"

      refute Process.alive?(collector)
    end
  end
end
