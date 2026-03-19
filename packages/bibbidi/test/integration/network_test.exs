defmodule Bibbidi.Integration.NetworkTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.BrowsingContext.Navigate
  alias Bibbidi.Commands.Script.Evaluate
  alias Bibbidi.Commands.Session.Subscribe
  alias Bibbidi.Commands.Network.{AddIntercept, ContinueRequest, ProvideResponse, RemoveIntercept}

  describe "function API" do
    test "intercept and continue request", %{conn: conn, context: context, base_url: base_url} do
      {:ok, _} = Session.subscribe(conn, ["network.beforeRequestSent"])
      :ok = Connection.subscribe(conn, "network.beforeRequestSent")

      {:ok, intercept_result} = Network.add_intercept(conn, ["beforeRequestSent"])
      intercept_id = intercept_result["intercept"]

      # Navigate in a task since it will block until the request is continued
      nav_task =
        Task.async(fn ->
          BrowsingContext.navigate(conn, context, "#{base_url}/hello", wait: "complete")
        end)

      # Wait for the intercept event
      assert_receive {:bibbidi_event, "network.beforeRequestSent", params}, 10_000
      request_id = params["request"]["request"]
      assert is_binary(request_id)
      assert params["request"]["url"] =~ "/hello"

      # Continue the request
      {:ok, _} = Network.continue_request(conn, request_id)

      # Navigation should complete
      assert {:ok, _} = Task.await(nav_task, 10_000)

      # Clean up
      {:ok, _} = Network.remove_intercept(conn, intercept_id)
    end

    test "provide mock response", %{conn: conn, context: context, base_url: base_url} do
      {:ok, _} = Session.subscribe(conn, ["network.beforeRequestSent"])
      :ok = Connection.subscribe(conn, "network.beforeRequestSent")

      {:ok, intercept_result} = Network.add_intercept(conn, ["beforeRequestSent"])
      intercept_id = intercept_result["intercept"]

      nav_task =
        Task.async(fn ->
          BrowsingContext.navigate(conn, context, "#{base_url}/hello", wait: "complete")
        end)

      assert_receive {:bibbidi_event, "network.beforeRequestSent", params}, 10_000
      request_id = params["request"]["request"]

      # Provide a mock response instead of continuing
      {:ok, _} =
        Network.provide_response(conn, request_id,
          status_code: 200,
          reason_phrase: "OK",
          headers: [%{name: "Content-Type", value: %{type: "string", value: "text/html"}}],
          body: %{type: "string", value: "<h1>Mocked</h1>"}
        )

      assert {:ok, _} = Task.await(nav_task, 10_000)

      # Verify the page content was replaced
      {:ok, result} =
        Script.evaluate(conn, "document.body.innerText", %{context: context}, true)

      assert result["result"]["value"] =~ "Mocked"

      {:ok, _} = Network.remove_intercept(conn, intercept_id)
    end
  end

  describe "struct API via Connection.execute/2" do
    test "intercept and continue request", %{conn: conn, context: context, base_url: base_url} do
      {:ok, _} = Connection.execute(conn, %Subscribe{events: ["network.beforeRequestSent"]})
      :ok = Connection.subscribe(conn, "network.beforeRequestSent")

      {:ok, intercept_result} =
        Connection.execute(conn, %AddIntercept{phases: ["beforeRequestSent"]})

      intercept_id = intercept_result["intercept"]

      nav_task =
        Task.async(fn ->
          Connection.execute(conn, %Navigate{
            context: context,
            url: "#{base_url}/hello",
            wait: "complete"
          })
        end)

      assert_receive {:bibbidi_event, "network.beforeRequestSent", params}, 10_000
      request_id = params["request"]["request"]
      assert is_binary(request_id)
      assert params["request"]["url"] =~ "/hello"

      {:ok, _} = Connection.execute(conn, %ContinueRequest{request: request_id})

      assert {:ok, _} = Task.await(nav_task, 10_000)

      {:ok, _} = Connection.execute(conn, %RemoveIntercept{intercept: intercept_id})
    end

    test "provide mock response", %{conn: conn, context: context, base_url: base_url} do
      {:ok, _} = Connection.execute(conn, %Subscribe{events: ["network.beforeRequestSent"]})
      :ok = Connection.subscribe(conn, "network.beforeRequestSent")

      {:ok, intercept_result} =
        Connection.execute(conn, %AddIntercept{phases: ["beforeRequestSent"]})

      intercept_id = intercept_result["intercept"]

      nav_task =
        Task.async(fn ->
          Connection.execute(conn, %Navigate{
            context: context,
            url: "#{base_url}/hello",
            wait: "complete"
          })
        end)

      assert_receive {:bibbidi_event, "network.beforeRequestSent", params}, 10_000
      request_id = params["request"]["request"]

      {:ok, _} =
        Connection.execute(conn, %ProvideResponse{
          request: request_id,
          status_code: 200,
          reason_phrase: "OK",
          headers: [%{name: "Content-Type", value: %{type: "string", value: "text/html"}}],
          body: %{type: "string", value: "<h1>Struct Mocked</h1>"}
        })

      assert {:ok, _} = Task.await(nav_task, 10_000)

      {:ok, result} =
        Connection.execute(conn, %Evaluate{
          expression: "document.body.innerText",
          target: %{context: context},
          await_promise: false
        })

      assert result["result"]["value"] =~ "Struct Mocked"

      {:ok, _} = Connection.execute(conn, %RemoveIntercept{intercept: intercept_id})
    end
  end
end
