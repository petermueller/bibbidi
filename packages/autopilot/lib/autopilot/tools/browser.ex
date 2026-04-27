defmodule Autopilot.Tools.Browser do
  @moduledoc "Browser action tools: navigate, click, type_text, press_key, scroll, go_back, get_links, get_current_url."

  alias LangChain.Function
  alias LangChain.FunctionParam

  def navigate do
    Function.new!(%{
      name: "navigate",
      description: "Navigate the browser to a URL.",
      parameters: [
        FunctionParam.new!(%{name: "url", type: :string, required: true,
          description: "Full URL e.g. 'https://google.com'"})
      ],
      function: fn %{"url" => url}, _context ->
        case Autopilot.Browser.navigate(url) do
          {:ok, _}         -> {:ok, "Navigated to #{url}"}
          {:error, reason} -> {:error, "navigate failed: #{inspect(reason)}"}
        end
      end
    })
  end

  @debug_click false

  def click do
    Function.new!(%{
      name: "click",
      description: """
      Click at x,y coordinates. Get coordinates from find_element first.

      Set verify=true when clicking to:
      - Close popups, modals, dialogs, overlays, cookie banners
      - Interact with custom  dropdowns, tabs, accordions, toggles or complex components
      - Dismiss ads or notifications
      - Any in-page component where navigation doesn't happen
      - If is possible to verify with dom don't apply Ai verify, like navigation confirmation

      When verify=true, provide expect with what should happen.
      The tool will take screenshots before and after, compare them with VLM,
      and tell you exactly what changed. Do NOT call see_screen after a verified click.
      """,
      parameters: [
        FunctionParam.new!(%{name: "x", type: :integer, required: true, description: "X coordinate"}),
        FunctionParam.new!(%{name: "y", type: :integer, required: true, description: "Y coordinate"}),
        FunctionParam.new!(%{name: "verify", type: :boolean, required: false,
          description: "Set true to visually verify what changed after clicking"}),
        FunctionParam.new!(%{name: "expect", type: :string, required: false,
          description: "What should happen, e.g. 'close the popup', 'open dropdown'. Required when verify=true."})
      ],
      function: fn args, _context ->
        x      = args["x"]
        y      = args["y"]
        verify = args["verify"] || false
        expect = args["expect"] || ""

        # Debug beacon
        if @debug_click do
          show_beacon(x, y)
          Process.sleep(2000)
        end

        if verify do
          click_with_verify(x, y, expect)
        else
          click_simple(x, y)
        end
      end
    })
  end

  defp click_simple(x, y) do
    Autopilot.TaskLog.log("CLICK", "(#{x}, #{y}) verify=false")
    case Autopilot.Browser.click(x, y) do
      {:ok, _}         -> {:ok, "Clicked at (#{x}, #{y})"}
      {:error, reason} -> {:error, "click failed: #{inspect(reason)}"}
    end
  end


  defp click_with_verify(x, y, expect) do
    Autopilot.TaskLog.log("CLICK", "(#{x}, #{y}) verify=true expect=#{expect}")
    # Screenshot BEFORE
    before_b64 = case Autopilot.Browser.screenshot() do
      {:ok, b64} -> b64
      _          -> nil
    end

    # Click
    case Autopilot.Browser.click(x, y) do
      {:ok, _} ->
        # Wait for page to react
        Process.sleep(800)

        # Screenshot AFTER
        after_b64 = case Autopilot.Browser.screenshot() do
          {:ok, b64} -> b64
          _          -> nil
        end

        # Compare via Vision API
        if before_b64 && after_b64 do
          case call_compare(before_b64, after_b64, expect) do
            {:ok, result} ->
              verdict   = result["verdict"] || "UNCLEAR"
              summary   = result["summary"] || ""
              changed   = result["changed"] || ""
              disappeared = result["disappeared"] || ""
              appeared  = result["appeared"] || ""

              {:ok, """
              Clicked at (#{x}, #{y}) — VERIFIED.
              VERDICT: #{verdict}
              EXPECTED: #{expect}
              CHANGED: #{changed}
              DISAPPEARED: #{disappeared}
              APPEARED: #{appeared}
              SUMMARY: #{summary}
              Do NOT call see_screen to double-check. Trust this result and move on.
              """}

            {:error, reason} ->
              {:ok, "Clicked at (#{x}, #{y}). Verification failed: #{inspect(reason)}. Use extract_text to check."}
          end
        else
          {:ok, "Clicked at (#{x}, #{y}). Could not take screenshots for verification."}
        end

      {:error, reason} ->
        {:error, "click failed: #{inspect(reason)}"}
    end
  end

  defp call_compare(before_b64, after_b64, expectation) do
    require Logger
    base = Application.get_env(:autopilot, :vision_url, "http://localhost:5001")

    Logger.debug("Vision /compare: expect=#{expectation}")

    case Req.post(base <> "/compare", json: %{
      before: before_b64,
      after: after_b64,
      expectation: expectation
    }, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: resp}} ->
        Logger.debug("Vision /compare OK: verdict=#{resp["verdict"]}")
        {:ok, resp}
      {:ok, %{status: status, body: resp}} ->
        Logger.error("Vision /compare #{status}: #{inspect(resp)}")
        {:error, "Vision API returned #{status}"}
      {:error, reason} ->
        Logger.error("Vision /compare error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp show_beacon(x, y) do
    js = """
    (function() {
      var dot = document.createElement('div');
      dot.style.cssText = 'position:fixed;left:#{x - 10}px;top:#{y - 10}px;width:20px;height:20px;' +
        'background:red;border-radius:50%;z-index:999999;pointer-events:none;' +
        'border:3px solid yellow;box-shadow:0 0 10px red;';
      dot.id = 'click-beacon';
      var old = document.getElementById('click-beacon');
      if (old) old.remove();
      document.body.appendChild(dot);
    })()
    """
    Autopilot.Browser.eval(js)
  end

  def type_text do
    Function.new!(%{
      name: "type_text",
      description: """
      Type text into an input field using native keyboard events.
      Works with React, Angular and other modern frameworks.
      Automatically focuses the field, clears existing content,
      and types character by character like a real keyboard.
      Use CSS selector from find_element or scan_dom.
      """,
      parameters: [
        FunctionParam.new!(%{name: "selector", type: :string, required: true,
          description: "CSS selector e.g. '#username', '[name=q]', 'input[type=email]'"}),
        FunctionParam.new!(%{name: "text", type: :string, required: true,
          description: "Text to type"})
      ],
      function: fn %{"selector" => selector, "text" => text}, _context ->
        case Autopilot.Browser.type(selector, text) do
          {:ok, _}         -> {:ok, "Typed '#{text}' into #{selector}"}
          {:error, reason} -> {:error, "type_text failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def press_key do
    Function.new!(%{
      name: "press_key",
      description: "Press a keyboard key. Use 'Enter' to submit, 'Tab' to move focus, 'Escape' to close.",
      parameters: [
        FunctionParam.new!(%{name: "key", type: :string, required: true,
          description: "Key name e.g. 'Enter', 'Tab', 'Escape', 'ArrowDown', 'Backspace'"})
      ],
      function: fn %{"key" => key}, _context ->
        case Autopilot.Browser.press_key(key) do
          {:ok, _}         -> {:ok, "Pressed '#{key}'"}
          {:error, reason} -> {:error, "press_key failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def scroll do
    Function.new!(%{
      name: "scroll",
      description: "Scroll the page up or down to reveal more content.",
      parameters: [
        FunctionParam.new!(%{name: "direction", type: :string, required: true,
          description: "'down' or 'up'"}),
        FunctionParam.new!(%{name: "amount", type: :integer, required: false,
          description: "Pixels to scroll (default 400)"})
      ],
      function: fn args, _context ->
        direction = args["direction"] || "down"
        amount    = args["amount"] || 400
        case Autopilot.Browser.scroll(direction, amount) do
          {:ok, _}         -> {:ok, "Scrolled #{direction} #{amount}px"}
          {:error, reason} -> {:error, "scroll failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def go_back do
    Function.new!(%{
      name: "go_back",
      description: "Go back to the previous page in browser history.",
      parameters: [],
      function: fn _args, _context ->
        case Autopilot.Browser.go_back() do
          {:ok, _}         -> {:ok, "Navigated back to previous page"}
          {:error, reason} -> {:error, "go_back failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def get_current_url do
    Function.new!(%{
      name: "get_current_url",
      description: "Get the current page URL without taking a screenshot.",
      parameters: [],
      function: fn _args, _context ->
        case Autopilot.Browser.eval("window.location.href") do
          {:ok, %{"result" => %{"value" => url}}} -> {:ok, url}
          {:error, reason}                         -> {:error, "get_current_url failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def get_links do
    Function.new!(%{
      name: "get_links",
      description: "Get all visible links on the page with their text and coordinates. Use to find search results or navigation links.",
      parameters: [
        FunctionParam.new!(%{name: "limit", type: :integer, required: false,
          description: "Max number of links to return (default 10)"})
      ],
      function: fn args, _context ->
        limit = args["limit"] || 10
        js = """
        JSON.stringify(
          Array.from(document.querySelectorAll('a[href]'))
            .filter(a => a.offsetParent !== null && a.textContent.trim().length > 0)
            .slice(0, #{limit})
            .map(a => ({
              text: a.textContent.trim().slice(0, 80),
              href: a.href,
              x:    Math.round(a.getBoundingClientRect().x + a.getBoundingClientRect().width  / 2),
              y:    Math.round(a.getBoundingClientRect().y + a.getBoundingClientRect().height / 2)
            }))
        )
        """
        case Autopilot.Browser.eval(js) do
          {:ok, %{"result" => %{"value" => json}}} ->
            links  = Jason.decode!(json)
            result = links
              |> Enum.map(fn l -> "[#{l["x"]}, #{l["y"]}] #{l["text"]} → #{l["href"]}" end)
              |> Enum.join("\n")
            {:ok, "Found #{length(links)} links:\n#{result}"}
          {:error, reason} ->
            {:error, "get_links failed: #{inspect(reason)}"}
        end
      end
    })
  end
end
