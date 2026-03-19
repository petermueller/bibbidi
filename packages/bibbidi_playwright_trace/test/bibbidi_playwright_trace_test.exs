defmodule BibbidiPlaywrightTraceTest do
  use ExUnit.Case, async: true

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

  @tag :tmp_dir
  test "start/stop produces a valid trace zip", %{conn: conn, tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "trace.zip")

    {:ok, collector} = BibbidiPlaywrightTrace.start(browser_name: "firefox", connection: conn)

    # Execute a few commands
    cmd1 = %Bibbidi.Commands.BrowsingContext.Navigate{
      context: "ctx-1",
      url: "https://example.com",
      wait: "complete"
    }

    task1 = Task.async(fn -> Connection.execute(conn, cmd1) end)
    assert_receive {:mock_transport_send, json1}
    decoded1 = Jason.decode!(json1)
    reply(conn, decoded1["id"], %{"navigation" => "nav-1", "url" => "https://example.com"})
    assert {:ok, _} = Task.await(task1)

    cmd2 = %Bibbidi.Commands.Script.Evaluate{
      expression: "document.title",
      target: %{context: "ctx-1"},
      await_promise: false
    }

    task2 = Task.async(fn -> Connection.execute(conn, cmd2) end)
    assert_receive {:mock_transport_send, json2}
    decoded2 = Jason.decode!(json2)
    reply(conn, decoded2["id"], %{"result" => %{"type" => "string", "value" => "Example"}})
    assert {:ok, _} = Task.await(task2)

    Process.sleep(50)

    assert :ok = BibbidiPlaywrightTrace.stop(collector, path)
    assert File.exists?(path)

    # Verify zip contents
    {:ok, [{~c"trace.trace", trace_data} | _]} =
      :zip.extract(String.to_charlist(path), [:memory, {:file_list, [~c"trace.trace"]}])

    lines =
      trace_data
      |> to_string()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    # context-options + 2 before/after pairs = 5 events
    assert length(lines) == 5

    assert Enum.at(lines, 0)["type"] == "context-options"
    assert Enum.at(lines, 0)["browserName"] == "firefox"

    assert Enum.at(lines, 1)["type"] == "before"
    assert Enum.at(lines, 1)["class"] == "browsingContext"
    assert Enum.at(lines, 1)["method"] == "navigate"

    assert Enum.at(lines, 2)["type"] == "after"
    assert Enum.at(lines, 2)["result"]["navigation"] == "nav-1"

    assert Enum.at(lines, 3)["type"] == "before"
    assert Enum.at(lines, 3)["class"] == "script"
    assert Enum.at(lines, 3)["method"] == "evaluate"

    assert Enum.at(lines, 4)["type"] == "after"
    assert Enum.at(lines, 4)["result"]["result"]["value"] == "Example"
  end

  @tag :tmp_dir
  test "peek/1 returns trace data without stopping", %{conn: conn, tmp_dir: _tmp_dir} do
    {:ok, collector} = BibbidiPlaywrightTrace.start(connection: conn)

    cmd = %Bibbidi.Commands.BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}
    task = Task.async(fn -> Connection.execute(conn, cmd) end)
    assert_receive {:mock_transport_send, json}
    reply(conn, Jason.decode!(json)["id"])
    Task.await(task)

    Process.sleep(50)

    {events, _resources} = BibbidiPlaywrightTrace.peek(collector)

    assert hd(events)["type"] == "context-options"
    # context-options + before + after = 3
    assert length(events) == 3

    assert Process.alive?(collector)

    GenServer.stop(collector)
  end

  @tag :tmp_dir
  test "screenshot data is extracted as resources", %{conn: conn, tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "trace.zip")

    {:ok, collector} = BibbidiPlaywrightTrace.start(connection: conn)

    cmd = %Bibbidi.Commands.BrowsingContext.CaptureScreenshot{context: "ctx-1"}
    task = Task.async(fn -> Connection.execute(conn, cmd) end)
    assert_receive {:mock_transport_send, json}
    decoded = Jason.decode!(json)

    fake_png = :crypto.strong_rand_bytes(64)
    reply(conn, decoded["id"], %{"data" => Base.encode64(fake_png)})
    assert {:ok, _} = Task.await(task)

    Process.sleep(50)

    assert :ok = BibbidiPlaywrightTrace.stop(collector, path)

    # Verify the resource is in the zip
    {:ok, files} = :zip.list_dir(String.to_charlist(path))

    resource_files =
      files
      |> Enum.filter(&match?({:zip_file, _, _, _, _, _}, &1))
      |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)
      |> Enum.filter(&String.starts_with?(&1, "resources/"))

    assert length(resource_files) == 1

    # Verify trace.trace has a screencast-frame event
    {:ok, [{~c"trace.trace", trace_data}]} =
      :zip.extract(String.to_charlist(path), [:memory, {:file_list, [~c"trace.trace"]}])

    lines =
      trace_data
      |> to_string()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    screencast = Enum.find(lines, &(&1["type"] == "screencast-frame"))
    assert screencast != nil
    assert screencast["pageId"] == "ctx-1"
  end
end
