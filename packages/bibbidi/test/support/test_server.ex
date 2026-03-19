defmodule Bibbidi.TestServer do
  @moduledoc false

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/hello" do
    send_resp(conn, 200, "<h1>Hello</h1>")
  end

  get "/console-log" do
    send_resp(conn, 200, ~s[<script>console.log("hello from test")</script>])
  end

  get "/slow" do
    Process.sleep(500)
    send_resp(conn, 200, "<h1>Slow</h1>")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  def start do
    {:ok, pid} = Bandit.start_link(plug: __MODULE__, port: 0, ip: :loopback)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    {:ok, pid, port}
  end
end
