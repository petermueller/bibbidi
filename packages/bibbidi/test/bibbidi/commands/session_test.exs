defmodule Bibbidi.Commands.SessionTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.Session

  describe "new/2" do
    test "sends session.new command with default capabilities" do
      expect_execute(fn _conn, cmd ->
        assert %Session.New{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "session.new"
        assert cmd.capabilities == %{}
      end)

      assert {:ok, %{}} = Session.new(:conn, %{}, connection_mod: MockConnection)
    end

    test "sends session.new command with custom capabilities" do
      caps = %{alwaysMatch: %{browserName: "chrome"}}

      expect_execute(fn _conn, cmd ->
        assert cmd.capabilities == caps
      end)

      Session.new(:conn, caps, connection_mod: MockConnection)
    end
  end

  describe "session_end/1" do
    test "sends session.end command" do
      expect_execute(fn _conn, cmd ->
        assert %Session.End{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "session.end"
        assert Bibbidi.Encodable.params(cmd) == %{}
      end)

      assert {:ok, %{}} = Session.session_end(:conn, connection_mod: MockConnection)
    end
  end

  describe "status/1" do
    test "sends session.status command" do
      expect_execute(fn _conn, cmd ->
        assert %Session.Status{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "session.status"
        assert Bibbidi.Encodable.params(cmd) == %{}
      end)

      assert {:ok, %{}} = Session.status(:conn, connection_mod: MockConnection)
    end
  end

  describe "subscribe/3" do
    test "sends session.subscribe command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "session.subscribe"
        assert cmd.events == ["browsingContext.load"]
        assert cmd.contexts == nil
      end)

      assert {:ok, %{}} =
               Session.subscribe(:conn, ["browsingContext.load"], connection_mod: MockConnection)
    end

    test "includes contexts option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.contexts == ["ctx-1"]
      end)

      Session.subscribe(:conn, ["log.entryAdded"],
        contexts: ["ctx-1"],
        connection_mod: MockConnection
      )
    end
  end

  describe "unsubscribe/3" do
    test "sends session.unsubscribe command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "session.unsubscribe"
        assert cmd.events == ["browsingContext.load"]
      end)

      assert {:ok, %{}} =
               Session.unsubscribe(:conn,
                 events: ["browsingContext.load"],
                 connection_mod: MockConnection
               )
    end
  end
end
