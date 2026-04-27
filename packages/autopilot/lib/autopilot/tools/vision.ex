defmodule Autopilot.Tools.Vision do
  @moduledoc "Vision tools: see_screen, embed_page, find_element, scan_dom, deep_search, extract_text, extract_article, segment, detect_captcha_grid, solve_captcha."

  alias LangChain.Function
  alias LangChain.FunctionParam

  @dom_scan_js """
  JSON.stringify(
    Array.from(document.querySelectorAll('input, textarea, select, [contenteditable]'))
      .filter(el => el.type !== 'hidden')
      .map((el, i) => {
        const r   = el.getBoundingClientRect();
        const sel = el.id   ? '#' + el.id
                  : el.name ? '[name=' + el.name + ']'
                  : 'input:nth-of-type(' + (i + 1) + ')';
        return {
          content:       el.placeholder || el.name || el.id || el.type || 'input',
          label:         el.placeholder || el.name || el.id || el.type || 'input',
          type:          el.tagName + ':' + (el.type || ''),
          interactivity: true,
          source:        'dom',
          selector:      sel,
          x:             Math.round(r.x + r.width  / 2),
          y:             Math.round(r.y + r.height / 2),
          visible:       el.offsetParent !== null
        }
      })
      .filter(el => el.x > 0 && el.y > 0)
  )
  """

  # ============================================
  # Tools
  # ============================================

  def see_screen do
    Function.new!(%{
      name: "see_screen",
      description: """
      Take a screenshot and analyze what is visible using a vision model.
      Use to understand page state, detect layout changes, verify actions worked.
      For reading text content, use extract_text or extract_article instead (lighter).
      """,
      parameters: [
        FunctionParam.new!(%{name: "question", type: :string, required: true,
          description: "What to analyze e.g. 'what is on this page?' or 'did the action work?'"})
      ],
      function: fn %{"question" => question}, _context ->
        with {:ok, b64}  <- Autopilot.Browser.screenshot(),
             {:ok, resp} <- call_vision("/see", %{screenshot: b64, question: question}) do
          description = resp["description"] || ""

          result = if detect_captcha(description) do
            description <> """

            \n⚠ CAPTCHA DETECTED — Follow this workflow:
            1. If it's an image-grid CAPTCHA: use solve_captcha() — it handles everything automatically.
            2. If it's a checkbox ("I'm not a robot"): try click(x, y) at the checkbox coordinates.
            3. Do NOT waste more than 2 attempts on the same CAPTCHA — switch sites instead.
            """
          else
            description
          end

          {:ok, result}
        else
          {:error, reason} -> {:error, "see_screen failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def embed_page do
    Function.new!(%{
      name: "embed_page",
      description: """
      Scan the current page and save all elements to the search index.
      Runs OmniParser + YOLO + DOM scan internally.
      Must be called before find_element works.
      Call again after layout changes (dropdowns, modals, overlays).
      """,
      parameters: [
        FunctionParam.new!(%{name: "url", type: :string, required: true,
          description: "Current page URL"})
      ],
      function: fn %{"url" => url}, _context ->
        with {:ok, b64}         <- Autopilot.Browser.screenshot(),
             {:ok, detect_resp} <- call_vision("/detect", %{screenshot: b64, url: url}) do

          detect_elements = detect_resp["elements"] || []

          dom_elements =
            case Autopilot.Browser.eval(@dom_scan_js) do
              {:ok, %{"result" => %{"value" => json}}} -> Jason.decode!(json)
              _                                         -> []
            end

          all_elements = detect_elements ++ dom_elements

          case call_vision("/embed", %{url: url, elements: all_elements}) do
            {:ok, resp} ->
              {:ok, "Indexed #{resp["stored"]} elements (skipped #{resp["skipped"]}) — sources: #{inspect(resp["sources"])}"}
            {:error, reason} ->
              {:error, "embed failed: #{inspect(reason)}"}
          end
        else
          {:error, reason} -> {:error, "embed_page failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def find_element do
    Function.new!(%{
      name: "find_element",
      description: """
      Search indexed elements by VISIBLE TEXT on the page.
      Query must match actual text you saw via see_screen — e.g. "Login", "Submit", "Ocean".
      NEVER use abstract queries like "first article" or "main button".
      Returns coordinates + CSS selector + href (for links).
      Requires embed_page to have been called first.
      If score < 0.3 or no results: try scan_dom + embed_page to refresh.
      """,
      parameters: [
        FunctionParam.new!(%{name: "query", type: :string, required: true,
          description: "Actual visible text to search for, e.g. 'Login', 'Ocean', 'Submit'"}),
        FunctionParam.new!(%{name: "url", type: :string, required: true,
          description: "Current page URL"}),
        FunctionParam.new!(%{name: "limit", type: :integer, required: false,
          description: "Number of results (default 5)"})
      ],
      function: fn args, _context ->
        query = args["query"]
        url   = args["url"]
        limit = args["limit"] || 5

        case call_vision("/find", %{query: query, url: url, limit: limit}) do
          {:ok, %{"matches" => []}} ->
            {:ok, "No elements found for '#{query}'. Try scan_dom + embed_page to refresh."}

          {:ok, %{"matches" => matches}} ->
            enriched = Enum.map(matches, fn m ->
              href = resolve_href(m["x"], m["y"], m["selector"])
              Map.put(m, "href", href)
            end)

            result = enriched
              |> Enum.map(fn m ->
                   selector = if m["selector"], do: " selector=#{m["selector"]}", else: ""
                   href     = if m["href"],     do: " href=#{m["href"]}",         else: " (no href — use click)"
                   "[#{m["x"]}, #{m["y"]}] #{m["content"]} score=#{m["score"]} source=#{m["source"]}#{selector}#{href}"
                 end)
              |> Enum.join("\n")
            {:ok, result}

          {:error, "not_found — call embed_page first"} ->
            {:ok, "Page not indexed. Call embed_page first."}

          {:error, reason} ->
            {:error, "find_element failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def scan_dom do
    Function.new!(%{
      name: "scan_dom",
      description: """
      Extract DOM input fields directly with selectors.
      Use when find_element misses inputs or for typing into form fields.
      Auto-indexes results so find_element works immediately after.
      """,
      parameters: [
        FunctionParam.new!(%{name: "url", type: :string, required: true,
          description: "Current page URL"})
      ],
      function: fn %{"url" => url}, _context ->
        case Autopilot.Browser.eval(@dom_scan_js) do
          {:ok, %{"result" => %{"value" => json}}} ->
            inputs  = Jason.decode!(json)
            summary = inputs
              |> Enum.map(fn i ->
                   "[#{i["x"]}, #{i["y"]}] #{i["content"]} selector=#{i["selector"]} visible=#{i["visible"]}"
                 end)
              |> Enum.join("\n")

            call_vision("/embed", %{url: url, elements: inputs})

            {:ok, "Found #{length(inputs)} DOM inputs (auto-indexed):\n#{summary}"}

          {:error, reason} ->
            {:error, "scan_dom failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def deep_search do
    Function.new!(%{
      name: "deep_search",
      description: """
      Visual element search using VLM + semantic search.
      Use when find_element and scan_dom fail to locate the element you need.
      Handles custom components, overlays, iframes, ad popups.
      Returns ranked candidates — pick the best match.
      """,
      parameters: [
        FunctionParam.new!(%{name: "question", type: :string, required: true,
          description: "What you need, e.g. 'how do I close the SUV popup?'"}),
        FunctionParam.new!(%{name: "url", type: :string, required: true,
          description: "Current page URL"})
      ],
      function: fn %{"question" => question, "url" => url}, _context ->
        with {:ok, b64}  <- Autopilot.Browser.screenshot(),
            {:ok, resp} <- call_vision("/deep_search", %{
              screenshot: b64, question: question, url: url
            }) do
          candidates = resp["candidates"] || []

          if candidates != [] do
            result = candidates
              |> Enum.with_index()
              |> Enum.map(fn {c, i} ->
                selector = if c["selector"], do: " selector=#{c["selector"]}", else: ""
                "[#{i}] (#{c["confidence"]}) [#{c["x"]}, #{c["y"]}] #{c["content"]}#{selector} via #{c["resolution"]}"
              end)
              |> Enum.join("\n")

            {:ok, "Found #{length(candidates)} candidate(s):\n#{result}\n\nVLM: #{resp["description"]}"}
          else
            {:ok, "No candidates found. VLM response: #{resp["description"]}"}
          end
        else
          {:error, reason} -> {:error, "deep_search failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def extract_text do
    Function.new!(%{
      name: "extract_text",
      description: """
      Extract visible text from the page DOM. Lightweight, no VLM.
      Use for quick checks or short content (up to 3000 chars).
      For full articles or lazy-loaded pages, use extract_article instead.
      """,
      parameters: [
        FunctionParam.new!(%{name: "limit", type: :integer, required: false,
          description: "Max characters to return (default 3000)"})
      ],
      function: fn args, _context ->
        limit = args["limit"] || 3000
        js    = "document.body.innerText.slice(0, #{limit})"

        case Autopilot.Browser.eval(js) do
          {:ok, %{"result" => %{"value" => text}}} ->
            {:ok, text}
          {:error, reason} ->
            {:error, "extract_text failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def extract_article do
    Function.new!(%{
      name: "extract_article",
      description: """
      Extract the full article/page content as clean text.
      Handles lazy-loaded content by scrolling and waiting for new content to appear.
      Use this instead of extract_text + scroll loops when reading long content.
      Returns the full page text (up to 15000 characters).
      """,
      parameters: [
        FunctionParam.new!(%{name: "limit", type: :integer, required: false,
          description: "Max characters to return (default 15000)"})
      ],
      function: fn args, _context ->
        limit = args["limit"] || 15_000

        js = """
        (async () => {
          const container = document.querySelector('article') ||
                            document.querySelector('[role="main"]') ||
                            document.querySelector('.post-content') ||
                            document.querySelector('.entry-content') ||
                            document.querySelector('.article-body') ||
                            document.querySelector('main') ||
                            document.body;

          const initialHeight = document.documentElement.scrollHeight;

          let lastHeight = 0;
          let stableCount = 0;
          const maxScrolls = 30;

          for (let i = 0; i < maxScrolls; i++) {
            window.scrollTo(0, document.documentElement.scrollHeight);
            await new Promise(r => setTimeout(r, 500));

            const newHeight = document.documentElement.scrollHeight;
            if (newHeight === lastHeight) {
              stableCount++;
              if (stableCount >= 2) break;
            } else {
              stableCount = 0;
            }
            lastHeight = newHeight;
          }

          window.scrollTo(0, 0);
          await new Promise(r => setTimeout(r, 200));

          const fullText = container.innerText.slice(0, #{limit});

          return JSON.stringify({
            text: fullText,
            length: fullText.length,
            scrolled: lastHeight > initialHeight,
            container: container.tagName.toLowerCase() +
              (container.className ? '.' + container.className.split(' ')[0] : '')
          });
        })()
        """

        try do
          case Autopilot.Browser.eval(js, 30_000) do
            {:ok, %{"result" => %{"value" => json}}} ->
              result = Jason.decode!(json)
              text = result["text"] || ""
              meta = if result["scrolled"],
                do: " (lazy-loaded content detected, scrolled to load all)",
                else: ""
              {:ok, "#{text}\n\n--- extracted #{result["length"]} chars from <#{result["container"]}>#{meta}"}
            {:error, reason} ->
              {:error, "extract_article failed: #{inspect(reason)}"}
          end
        catch
          :exit, {:timeout, _} ->
            {:ok, "extract_article timed out. Try extract_text instead."}
        end
      end
    })
  end

  def detect_captcha_grid do
    Function.new!(%{
      name: "detect_captcha_grid",
      description: """
      Detect the CAPTCHA image grid bounding box using a dedicated YOLO model.
      Returns the grid coordinates {x1, y1, x2, y2, width, height}.
      For most cases, use solve_captcha instead — it does everything in one call.
      """,
      parameters: [],
      function: fn _args, _context ->
        with {:ok, b64}  <- Autopilot.Browser.screenshot(),
             {:ok, resp} <- call_vision("/detect_grid", %{screenshot: b64}) do

          if resp["found"] do
            g = resp["grid"]
            {:ok, "Grid found: x1=#{g["x1"]} y1=#{g["y1"]} x2=#{g["x2"]} y2=#{g["y2"]} " <>
                 "size=#{g["width"]}x#{g["height"]} conf=#{g["confidence"]}"}
          else
            {:ok, "No CAPTCHA grid detected in screenshot."}
          end
        else
          {:error, reason} -> {:error, "detect_captcha_grid failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def solve_captcha do
    Function.new!(%{
      name: "solve_captcha",
      description: """
      All-in-one CAPTCHA image grid solver. Takes a screenshot and returns
      exactly which grid cells to click.

      IMPORTANT: Call this ONLY ONCE per CAPTCHA. After clicking the returned
      cells, your next step is to click the VERIFY button — NOT to call
      solve_captcha again. Re-running deselects your previous clicks.

      Internally: detects grid (YOLO) → identifies object + grid type (VLM) →
      segments object (SAM3) → maps mask to grid cells.

      Returns a list of click_targets with {x, y} coordinates.
      Click each coordinate, then click VERIFY/NEXT.
      """,
      parameters: [
        FunctionParam.new!(%{name: "object_hint", type: :string, required: false,
          description: "What to find, e.g. 'bus', 'bicycle'. If empty, VLM detects it."}),
        FunctionParam.new!(%{name: "rows", type: :integer, required: false,
          description: "Grid rows (3 or 4). If 0, VLM detects it."}),
        FunctionParam.new!(%{name: "cols", type: :integer, required: false,
          description: "Grid cols (3 or 4). If 0, VLM detects it."})
      ],
      function: fn args, _context ->
        object_hint = args["object_hint"] || ""
        rows        = args["rows"] || 0
        cols        = args["cols"] || 0

        with {:ok, b64}  <- Autopilot.Browser.screenshot(),
             {:ok, resp} <- call_vision("/solve", %{
               screenshot:  b64,
               object_hint: object_hint,
               rows:        rows,
               cols:        cols
             }) do

          if resp["solved"] do
            targets = resp["click_targets"] || []
            coords = targets
              |> Enum.map(fn t -> "  click(#{t["x"]}, #{t["y"]})  # cell [#{t["row"]},#{t["col"]}]" end)
              |> Enum.join("\n")

            {:ok, """
              CAPTCHA solved: '#{resp["prompt"]}' #{resp["rows"]}x#{resp["cols"]} grid
              Click these #{length(targets)} cell(s) in order, ONCE each:
              #{coords}

              CRITICAL NEXT STEPS (DO ALL OF THESE, DO NOT CALL solve_captcha OR segment AGAIN):
              1. Click each cell above, exactly once.
              2. Call find_element with query="Verify" or "Next" or "Skip" to locate the verify button.
              3. Click the verify button.
              4. Then call see_screen to check the result.

              WARNING: clicking a cell twice DESELECTS it. Do NOT re-run solve_captcha
              after clicking — the cells you selected will be undone.
              """}
          else
            {:ok, "CAPTCHA solve failed: #{resp["error"] || "unknown error"}"}
          end
        else
          {:error, reason} -> {:error, "solve_captcha failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def segment do
    Function.new!(%{
      name: "segment",
      description: """
      Use SAM3 to find and segment visual elements by text description.
      Returns click_targets — a list of {x, y} coordinates to click.

      For CAPTCHA grids, pass the grid parameter so the mask gets mapped
      to individual grid cells. Without grid, returns one click per instance.
      """,
      parameters: [
        FunctionParam.new!(%{
          name:        "prompts",
          type:        :array,
          item_type:   "string",
          required:    true,
          description: "List of visual descriptions to find e.g. ['traffic light', 'bus']"
        }),
        FunctionParam.new!(%{
          name:        "grid",
          type:        :object,
          required:    false,
          description: "CAPTCHA grid bounds from detect_captcha_grid.",
          object_properties: [
            FunctionParam.new!(%{name: "x1",   type: :integer, required: true, description: "Grid left x"}),
            FunctionParam.new!(%{name: "y1",   type: :integer, required: true, description: "Grid top y"}),
            FunctionParam.new!(%{name: "x2",   type: :integer, required: true, description: "Grid right x"}),
            FunctionParam.new!(%{name: "y2",   type: :integer, required: true, description: "Grid bottom y"}),
            FunctionParam.new!(%{name: "rows", type: :integer, required: true, description: "Number of rows (3 or 4)"}),
            FunctionParam.new!(%{name: "cols", type: :integer, required: true, description: "Number of columns (3 or 4)"})
          ]
        }),
        FunctionParam.new!(%{
          name:        "save_annotated",
          type:        :boolean,
          required:    false,
          description: "Save annotated debug image to disk (default true)"
        })
      ],
      function: fn args, _context ->
        prompts        = args["prompts"] || []
        save_annotated = args["save_annotated"] || true
        grid           = args["grid"]

        body = %{
          screenshot:     nil,
          prompts:        prompts,
          save_annotated: save_annotated
        }
        body = if grid, do: Map.put(body, :grid, grid), else: body

        with {:ok, b64}  <- Autopilot.Browser.screenshot(),
             {:ok, resp} <- call_vision("/segment", Map.put(body, :screenshot, b64)) do

          results = resp["results"] || []
          found   = Enum.filter(results, & &1["found"])

          if Enum.empty?(found) do
            {:ok, "No elements found for prompts: #{inspect(prompts)}"}
          else
            summary = found
              |> Enum.map(fn r ->
                   targets = r["click_targets"] || [r["click_target"]]
                   coords  = targets
                     |> Enum.map(fn t -> "(#{t["x"]}, #{t["y"]})" end)
                     |> Enum.join(", ")
                   "#{r["prompt"]} instance=#{r["instance_id"]} area=#{r["mask_area_px"]}px → click: #{coords}"
                 end)
              |> Enum.join("\n")

            total_clicks = found
              |> Enum.flat_map(fn r -> r["click_targets"] || [r["click_target"]] end)
              |> length()

            {:ok, """
              Found #{length(found)} instance(s), #{total_clicks} click target(s):
              #{summary}

              After clicking these, if this was a CAPTCHA: find and click the VERIFY button next.
              Do NOT call segment or solve_captcha again — re-clicking the same cells DESELECTS them.
              """}
          end
        else
          {:error, reason} -> {:error, "segment failed: #{inspect(reason)}"}
        end
      end
    })
  end

  # ============================================
  # Private
  # ============================================

  @captcha_keywords ["captcha", "recaptcha", "hcaptcha", "not a robot", "verify you",
                     "unusual traffic", "security check"]

  defp detect_captcha(text) do
    lower = String.downcase(text)
    Enum.any?(@captcha_keywords, &String.contains?(lower, &1))
  end

  defp resolve_href(x, y, selector) do
    js = cond do
      is_binary(selector) and selector != "" ->
        """
        (function() {
          var el = document.querySelector('#{String.replace(selector, "'", "\\'")}');
          if (!el) return null;
          var a = el.closest('a[href]') || el.querySelector('a[href]');
          return a ? a.href : null;
        })()
        """

      is_integer(x) and is_integer(y) and x > 0 and y > 0 ->
        """
        (function() {
          var el = document.elementFromPoint(#{x}, #{y});
          if (!el) return null;
          var a = el.closest('a[href]');
          return a ? a.href : null;
        })()
        """

      true -> "null"
    end

    case Autopilot.Browser.eval(js) do
      {:ok, %{"result" => %{"value" => href}}} when is_binary(href) -> href
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp call_vision(path, body) do
    require Logger
    base = Application.get_env(:autopilot, :vision_url, "http://localhost:5001")

    clean_body = Map.drop(body, [:screenshot, "screenshot"])
    Logger.debug("Vision #{path}: #{inspect(clean_body)}")
    Autopilot.TaskLog.log("API_REQ", "#{path} #{inspect(clean_body, limit: :infinity, printable_limit: 4000)}")

    start = System.monotonic_time(:millisecond)

    result = case Req.post(base <> path, json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: resp_body}} ->
        clean_resp = Map.drop(resp_body, ["annotated_image", "original_image", "annotated_b64", "elements"])
        Logger.debug("Vision #{path} OK: #{inspect(clean_resp)}")
        {:ok, resp_body}

      {:ok, %{status: 404}} ->
        {:error, "not_found — call embed_page first"}

      {:ok, %{status: 503}} ->
        {:error, "Model not loaded yet — wait for startup"}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("Vision #{path} #{status}: #{inspect(resp_body)}")
        {:error, "Vision API returned #{status}"}

      {:error, reason} ->
        Logger.error("Vision #{path} error: #{inspect(reason)}")
        {:error, reason}
    end

    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, resp_body} ->
        clean_resp = Map.drop(resp_body, ["annotated_image", "original_image", "annotated_b64", "elements"])
        Autopilot.TaskLog.log("API_RES", "#{path} 200 (#{elapsed}ms)\n#{inspect(clean_resp, limit: :infinity, printable_limit: 4000)}")
      {:error, reason} ->
        Autopilot.TaskLog.log("API_ERR", "#{path} (#{elapsed}ms) #{inspect(reason)}")
    end

    result
  end
end
