defmodule BibbidiPlaywrightTrace.WriterTest do
  use ExUnit.Case, async: true

  alias BibbidiPlaywrightTrace.Writer

  describe "context_options/1" do
    test "builds context-options event with defaults" do
      event = Writer.context_options([])

      assert event["type"] == "context-options"
      assert event["browserName"] == "unknown"
      assert event["origin"] == "library"
      assert is_integer(event["wallTime"])
      assert is_integer(event["monotonicTime"])
      assert event["options"] == %{}
    end

    test "includes browser name and viewport" do
      event =
        Writer.context_options(
          browser_name: "firefox",
          viewport: {1280, 720}
        )

      assert event["browserName"] == "firefox"
      assert event["options"] == %{"viewport" => %{"width" => 1280, "height" => 720}}
    end

    test "accepts viewport as map" do
      event = Writer.context_options(viewport: %{width: 800, height: 600})
      assert event["options"]["viewport"] == %{"width" => 800, "height" => 600}
    end
  end

  describe "before_event/4" do
    test "builds before event splitting BiDi method into class and method" do
      event = Writer.before_event("call@1", 1000, "browsingContext.navigate", %{"url" => "https://example.com"})

      assert event["type"] == "before"
      assert event["callId"] == "call@1"
      assert event["startTime"] == 1000
      assert event["class"] == "browsingContext"
      assert event["method"] == "navigate"
      assert event["params"] == %{"url" => "https://example.com"}
    end

    test "handles method without dot separator" do
      event = Writer.before_event("call@1", 1000, "status", %{})

      assert event["class"] == "bibbidi"
      assert event["method"] == "status"
    end
  end

  describe "after_event/3" do
    test "builds after event for success" do
      event = Writer.after_event("call@1", 2000, {:ok, %{"navigation" => "nav-1"}})

      assert event["type"] == "after"
      assert event["callId"] == "call@1"
      assert event["endTime"] == 2000
      assert event["result"] == %{"navigation" => "nav-1"}
      refute Map.has_key?(event, "error")
    end

    test "builds after event for error" do
      event = Writer.after_event("call@1", 2000, {:error, :timeout})

      assert event["type"] == "after"
      assert event["callId"] == "call@1"
      assert event["endTime"] == 2000
      assert event["error"] == %{"message" => ":timeout"}
      refute Map.has_key?(event, "result")
    end
  end

  describe "bidi_event/3" do
    test "builds event entry from BiDi event" do
      event = Writer.bidi_event(1500, "browsingContext.load", %{"context" => "ctx-1"})

      assert event["type"] == "event"
      assert event["time"] == 1500
      assert event["class"] == "browsingContext"
      assert event["method"] == "load"
      assert event["params"] == %{"context" => "ctx-1"}
    end
  end

  describe "screencast_frame/4" do
    test "builds screencast-frame event with SHA1 resource key" do
      # A small 1x1 red PNG pixel
      png_data = Base.encode64(<<0, 0, 0, 1, 2, 3>>)

      {event, sha1, binary} = Writer.screencast_frame("page@1", 1500, png_data, width: 1, height: 1)

      assert event["type"] == "screencast-frame"
      assert event["pageId"] == "page@1"
      assert event["sha1"] == sha1
      assert event["width"] == 1
      assert event["height"] == 1
      assert event["timestamp"] == 1500
      assert is_binary(sha1)
      assert byte_size(sha1) == 40
      assert binary == <<0, 0, 0, 1, 2, 3>>
    end
  end

  describe "write_zip/3" do
    @tag :tmp_dir
    test "produces a valid zip with trace.trace and trace.network", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.zip")

      events = [
        Writer.context_options(browser_name: "firefox"),
        Writer.before_event("call@1", 1000, "browsingContext.navigate", %{"url" => "https://example.com"}),
        Writer.after_event("call@1", 2000, {:ok, %{"navigation" => "nav-1"}})
      ]

      assert :ok = Writer.write_zip(path, events)
      assert File.exists?(path)

      {:ok, files} = :zip.list_dir(String.to_charlist(path))

      # First entry is zip_comment, rest are zip_file entries
      file_names =
        files
        |> Enum.filter(&match?({:zip_file, _, _, _, _, _}, &1))
        |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

      assert "trace.trace" in file_names
      assert "trace.network" in file_names
    end

    @tag :tmp_dir
    test "trace.trace contains NDJSON lines", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.zip")

      events = [
        Writer.context_options(browser_name: "chromium"),
        Writer.before_event("call@1", 1000, "script.evaluate", %{"expression" => "1+1"}),
        Writer.after_event("call@1", 1100, {:ok, %{"result" => %{"value" => 2}}})
      ]

      :ok = Writer.write_zip(path, events)

      {:ok, [{~c"trace.trace", trace_data} | _]} =
        :zip.extract(String.to_charlist(path), [:memory, {:file_list, [~c"trace.trace"]}])

      lines =
        trace_data
        |> to_string()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert length(lines) == 3

      assert Enum.at(lines, 0)["type"] == "context-options"
      assert Enum.at(lines, 1)["type"] == "before"
      assert Enum.at(lines, 1)["callId"] == "call@1"
      assert Enum.at(lines, 2)["type"] == "after"
      assert Enum.at(lines, 2)["callId"] == "call@1"
    end

    @tag :tmp_dir
    test "includes resources in zip", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.zip")

      events = [Writer.context_options()]
      resources = %{"abc123def456" => <<1, 2, 3, 4>>}

      :ok = Writer.write_zip(path, events, resources)

      {:ok, [{_, resource_data}]} =
        :zip.extract(String.to_charlist(path), [
          :memory,
          {:file_list, [~c"resources/abc123def456"]}
        ])

      assert resource_data == <<1, 2, 3, 4>>
    end
  end
end
