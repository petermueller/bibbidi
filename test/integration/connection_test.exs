defmodule Bibbidi.Integration.ConnectionTest do
  use Bibbidi.IntegrationCase

  test "concurrent command correlation", %{conn: conn, context: context} do
    tasks =
      for i <- 1..3 do
        Task.async(fn ->
          Script.evaluate(conn, "#{i} * 10", %{context: context})
        end)
      end

    results = Task.await_many(tasks, 10_000)

    values =
      results
      |> Enum.map(fn {:ok, result} -> result["result"]["value"] end)
      |> Enum.sort()

    assert values == [10, 20, 30]
  end

  test "error response for invalid context", %{conn: conn} do
    result = Script.evaluate(conn, "1 + 1", %{context: "invalid-context-id"})

    assert {:error, %{error: error, message: message}} = result
    assert is_binary(error)
    assert is_binary(message)
  end

  test "session status", %{conn: conn} do
    {:ok, result} = Session.status(conn)
    assert Map.has_key?(result, "ready")
    assert Map.has_key?(result, "message")
  end
end
