defmodule Autopilot.Browser do
  @moduledoc "Manages Bibbidi browser connection and common actions."

  use GenServer

  alias Bibbidi.Commands.{BrowsingContext, Script, Input}

  @key_map %{
    "Enter"      => "\uE007",
    "Tab"        => "\uE004",
    "Escape"     => "\uE00C",
    "Backspace"  => "\uE003",
    "ArrowDown"  => "\uE015",
    "ArrowUp"    => "\uE013",
    "ArrowLeft"  => "\uE012",
    "ArrowRight" => "\uE014",
    "Space"      => "\uE00D",
    "Delete"     => "\uE017",
    "Home"       => "\uE011",
    "End"        => "\uE010"
  }

  # --- Public API ---

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def navigate(url),          do: GenServer.call(__MODULE__, {:navigate, url}, 30_000)
  def screenshot,             do: GenServer.call(__MODULE__, :screenshot, 15_000)
  def click(x, y),            do: GenServer.call(__MODULE__, {:click, x, y}, 10_000)
  def type(selector, text),   do: GenServer.call(__MODULE__, {:type, selector, text}, 15_000)
  def press_key(key),         do: GenServer.call(__MODULE__, {:press_key, key}, 10_000)
  def scroll(direction, amount \\ 400), do: GenServer.call(__MODULE__, {:scroll, direction, amount}, 10_000)
  def go_back,                do: GenServer.call(__MODULE__, :go_back, 15_000)
  def eval(js, timeout \\ 15_000), do: GenServer.call(__MODULE__, {:eval, js}, timeout)

  # --- GenServer ---

  @impl true
  def init(opts) do
    case {Keyword.get(opts, :conn), Keyword.get(opts, :context)} do
      {conn, context} when conn != nil and context != nil ->
        IO.puts(">> Browser: using shared connection")
        {:ok, %{conn: conn, context: context}}

      _ ->
        browser = Application.get_env(:autopilot, :browser, "firefox")
        case browser do
          "firefox" ->
            ws_url = Application.get_env(:autopilot, :firefox_ws_url, "ws://localhost:9222")
            connect_firefox(ws_url)
          "chrome" ->
            url = Application.get_env(:autopilot, :chromedriver_url, "http://localhost:9515")
            connect_chrome(url)
          other ->
            {:stop, "Unknown browser: #{other}"}
        end
    end
  end

  defp connect_firefox(ws_url) do
    IO.puts(">> Firefox BiDi: #{ws_url}")

    with {:ok, conn}  <- Bibbidi.Connection.start_link(url: ws_url),
        {:ok, _caps} <- Bibbidi.Session.new(conn),
        {:ok, tree}  <- BrowsingContext.get_tree(conn) do
      context = hd(tree["contexts"])["context"]
      {:ok, %{conn: conn, context: context}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp connect_chrome(chromedriver_url) do
    IO.puts(">> Creating Chrome session via #{chromedriver_url}")

    body = %{
      "capabilities" => %{
        "alwaysMatch" => %{
          "browserName" => "chrome",
          "goog:chromeOptions" => %{
            "args" => [
              #"--headless=new",
              "--disable-gpu",
              "--window-size=1280,900"
            ]
          },
          "webSocketUrl" => true
        }
      }
    }

    case Req.post("#{chromedriver_url}/session", json: body) do
      {:ok, %{status: 200, body: resp}} ->
        ws_url = get_in(resp, ["value", "capabilities", "webSocketUrl"])
        session_id = get_in(resp, ["value", "sessionId"])
        IO.puts(">> Chrome BiDi WS: #{ws_url}")

        with {:ok, conn} <- Bibbidi.Connection.start_link(url: ws_url),
            {:ok, tree} <- BrowsingContext.get_tree(conn) do
          context = hd(tree["contexts"])["context"]
          {:ok, %{conn: conn, context: context, session_id: session_id}}
        else
          {:error, reason} -> {:stop, reason}
        end

      {:ok, %{status: status, body: err}} ->
        {:stop, "ChromeDriver session failed (#{status}): #{inspect(err)}"}

      {:error, reason} ->
        {:stop, "Can't reach ChromeDriver: #{inspect(reason)}"}
    end
  end

  @impl true
  def handle_call({:navigate, url}, _from, %{conn: conn, context: ctx} = state) do
    #result = BrowsingContext.navigate(conn, ctx, url, wait: "complete")
    result = BrowsingContext.navigate(conn, ctx, url, wait: "interactive")
    {:reply, result, state}
  end

  def handle_call(:screenshot, _from, %{conn: conn, context: ctx} = state) do
    case BrowsingContext.capture_screenshot(conn, ctx) do
      {:ok, %{"data" => b64}} -> {:reply, {:ok, b64}, state}
      error                   -> {:reply, error, state}
    end
  end

  def handle_call({:click, x, y}, _from, %{conn: conn, context: ctx} = state) do
    # Use BiDi pointer actions (not JS) so clicks penetrate cross-origin iframes
    result = Input.perform_actions(conn, ctx, [
      %{
        "type" => "pointer",
        "id"   => "mouse",
        "parameters" => %{"pointerType" => "mouse"},
        "actions" => [
          %{"type" => "pointerMove", "x" => x, "y" => y},
          %{"type" => "pointerDown", "button" => 0},
          %{"type" => "pointerUp",   "button" => 0}
        ]
      }
    ])
    {:reply, result, state}
  end

  def handle_call({:type, selector, text}, _from, %{conn: conn, context: ctx} = state) do
    # 1. Focus the element via JS
    Script.evaluate(conn, """
    (function() {
      const el = document.querySelector('#{selector}');
      if (el) { el.focus(); el.click(); }
    })()
    """, %{context: ctx}, false)

    # 2. Clear existing value via Ctrl+A + Delete
    Input.perform_actions(conn, ctx, [
      %{"type" => "key", "id" => "keyboard", "actions" => [
        %{"type" => "keyDown", "value" => "\uE009"},  # Ctrl down
        %{"type" => "keyDown", "value" => "a"},
        %{"type" => "keyUp",   "value" => "a"},
        %{"type" => "keyUp",   "value" => "\uE009"},  # Ctrl up
        %{"type" => "keyDown", "value" => "\uE017"},  # Delete
        %{"type" => "keyUp",   "value" => "\uE017"}
      ]}
    ])

    # 3. Type character by character via native BiDi keyboard events
    actions = text
      |> String.graphemes()
      |> Enum.flat_map(fn char ->
           [
             %{"type" => "keyDown", "value" => char},
             %{"type" => "keyUp",   "value" => char}
           ]
         end)

    result = Input.perform_actions(conn, ctx, [
      %{"type" => "key", "id" => "keyboard", "actions" => actions}
    ])

    {:reply, result, state}
  end

  def handle_call({:press_key, key}, _from, %{conn: conn, context: ctx} = state) do
    Script.evaluate(conn, "document.activeElement.focus()", %{context: ctx}, false)

    key_val = Map.get(@key_map, key, key)

    result = Input.perform_actions(conn, ctx, [
      %{
        "type" => "key",
        "id"   => "keyboard",
        "actions" => [
          %{"type" => "keyDown", "value" => key_val},
          %{"type" => "keyUp",   "value" => key_val}
        ]
      }
    ])
    {:reply, result, state}
  end

  def handle_call({:scroll, direction, amount}, _from, %{conn: conn, context: ctx} = state) do
    delta_y = if direction == "down", do: amount, else: -amount

    result = Input.perform_actions(conn, ctx, [
      %{
        "type" => "wheel",
        "id"   => "wheel",
        "actions" => [
          %{
            "type"   => "scroll",
            "x"      => 0,
            "y"      => 0,
            "deltaX" => 0,
            "deltaY" => delta_y
          }
        ]
      }
    ])
    {:reply, result, state}
  end

  def handle_call(:go_back, _from, %{conn: conn, context: ctx} = state) do
    result = BrowsingContext.traverse_history(conn, ctx, -1)
    {:reply, result, state}
  end

  def handle_call({:eval, js}, _from, %{conn: conn, context: ctx} = state) do
    result = Script.evaluate(conn, js, %{context: ctx}, false)
    {:reply, result, state}
  end
end
