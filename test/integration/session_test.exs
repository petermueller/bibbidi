defmodule Bibbidi.Integration.SessionTest do
  use Bibbidi.IntegrationCase

  test "subscribe and unsubscribe round-trip", %{conn: conn} do
    {:ok, _} = Session.subscribe(conn, ["log.entryAdded"])
    {:ok, _} = Session.unsubscribe(conn, ["log.entryAdded"])
  end

  test "status returns ready and message", %{conn: conn} do
    {:ok, result} = Session.status(conn)
    assert is_boolean(result["ready"])
    assert is_binary(result["message"])
  end
end
