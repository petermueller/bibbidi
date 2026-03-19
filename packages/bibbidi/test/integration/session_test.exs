defmodule Bibbidi.Integration.SessionTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.Session.{Subscribe, Unsubscribe, Status}

  describe "function API" do
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

  describe "struct API via Connection.execute/2" do
    test "subscribe and unsubscribe round-trip", %{conn: conn} do
      {:ok, _} = Connection.execute(conn, %Subscribe{events: ["log.entryAdded"]})
      {:ok, _} = Connection.execute(conn, %Unsubscribe{events: ["log.entryAdded"]})
    end

    test "status returns ready and message", %{conn: conn} do
      {:ok, result} = Connection.execute(conn, %Status{})
      assert is_boolean(result["ready"])
      assert is_binary(result["message"])
    end
  end
end
