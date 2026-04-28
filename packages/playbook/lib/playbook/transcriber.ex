defmodule Playbook.Transcriber do
  @moduledoc """
  Converts a raw session log into a structured playbook JSON.

  Single-shot: sends the log to the LLM and expects a JSON response.
  No questions, no interaction — uses sensible defaults to handle
  ambiguity automatically.

  ## Usage

      {:ok, name, log} = Playbook.Recorder.end_session()
      {:ok, playbook} = Playbook.Transcriber.generate(name, log, llm_fn)
  """

  require Logger

  alias Playbook.LogEntry

  @type llm_fn :: (String.t(), String.t() -> {:ok, String.t()} | {:error, term()})

  @doc """
  Generate a playbook from a session log.

  The `llm_fn` receives (system_prompt, user_message) and returns {:ok, response}.
  """
  @spec generate(String.t(), [LogEntry.t()], llm_fn(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def generate(session_name, log, llm_fn, _opts \\ []) do
    log_text = format_log(log)
    system = system_prompt()
    user_msg = user_prompt(session_name, log_text)

    Logger.info("[Transcriber] Analyzing #{length(log)} events for \"#{session_name}\"")

    case llm_fn.(system, user_msg) do
      {:ok, response} -> parse_playbook(response)
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Prompt construction ────────────────────────────────────────

  defp system_prompt do
    """
    You are a Playbook Transformer. You convert a raw browser session log
    into a clean, structured playbook JSON for RPA automation.

    YOU MUST OUTPUT ONLY VALID JSON. NO QUESTIONS. NO COMMENTARY. NO MARKDOWN.
    NO PREAMBLE. NO EXPLANATION. Start your output with `{` and end with `}`.

    ANY non-JSON output is a CRITICAL ERROR. Use sensible defaults instead of asking.

    ## Default rules (apply automatically — never ask)

    1. **Modals/popups/cookie banners** → emit as conditional steps with
       `condition: "element_visible"` and `condition_value: <selector>`.
       Treat ANY annotation containing "popup", "modal", "optional",
       "conditional", "dialog" as a strong signal for `condition`.

    2. **Incremental typing on the same selector** → collapse into ONE `type`
       step with the FINAL value typed. Discard intermediate inputs.

    3. **Duplicate consecutive navigations to the same URL** → keep only the
       first one.

    4. **Background / tracking navigations** → DISCARD entirely. This includes
       URLs containing: googletagmanager, doubleclick, googlesyndication,
       google-analytics, googleadservices, googletagservices, recaptcha,
       cloudflareinsights, hotjar, segment.io, fullstory, /pixel, /tracking,
       /ads/, /analytics/, /collect, /beacon, fbcq, fbevents.

    5. **iframe / embed navigations** (youtube embed, ad iframes) → DISCARD.

    6. **Accidental clicks** (clicks with no resulting action, clicks on
       `<body>`, `<html>`, `<main>` with no interactive child) → DISCARD
       unless followed by an immediate observable change.

    7. **Final state** → playbook should end at the last MEANINGFUL action
       (the one that fulfills the goal). Trailing modal closes / cleanup
       should be conditional optional steps after the goal completes.

    8. **Password / sensitive fields** → ALWAYS use `human: true` and
       `variable: "password"` (or appropriate name). Never include the
       captured value.

    9. **Login fields** (username, email, etc.) → use `variable` template
       like `{username}`, `{email}` rather than hardcoded values when the
       value looks like a credential.

    10. **Search queries / free-form user input** → KEEP the typed value
        verbatim, no variable.

    Prefer FEWER, cleaner steps. The output should be the minimum set of
    actions needed to reproduce the user's goal reliably.

    ## Step types

    - goto:         Navigate to a URL (use `value`)
    - click:        Click an element (use `selector`)
    - type:         Type text into an input (use `selector` + `value` or `variable`)
    - press_key:    Press a key like Enter or Tab (use `value`)
    - wait_url:     Wait for URL to contain string (use `value`)
    - wait_element: Wait for element to appear (use `selector`)
    - assert_url:   Verify current URL (use `value`)
    - human:        Pause for human action (use `label`)
    - extract:      Read text content from an element and save it (use `selector` + `variable`)

    ## Step properties

    - action            (required)
    - selector          (CSS selector)
    - value             (text to type, URL, or string to wait for)
    - variable          (template variable name, e.g. "password")
    - label             (short human description, REQUIRED)
    - condition         ("element_visible" | "url_contains" | "text_on_page")
    - condition_value   (selector/url/text checked by the condition)
    - human             (boolean, true if step requires human interaction)

    ## Output schema (THIS EXACT SHAPE)

    {
      "name": "<session name>",
      "goal": "<one-sentence description of what the playbook does>",
      "steps": [
        { "action": "...", "label": "...", ... }
      ]
    }

    REMEMBER: Output ONLY the JSON object. Nothing before. Nothing after.
    """
  end

  defp user_prompt(session_name, log_text) do
    """
    Session name: "#{session_name}"

    Raw event log (numbered):
    #{log_text}

    Generate the playbook JSON now. Apply all default rules. Do not ask
    questions. Do not include explanations. Output ONLY the JSON object.
    """
  end

  # ── Log formatting ─────────────────────────────────────────────

  defp format_log(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, i} ->
      "#{String.pad_leading(Integer.to_string(i), 3, "0")}. #{LogEntry.to_log_line(entry)}"
    end)
    |> Enum.join("\n")
  end

  # ── JSON parsing ───────────────────────────────────────────────

  defp parse_playbook(text) do
    cleaned = clean_json(text)

    case Jason.decode(cleaned) do
      {:ok, %{"steps" => steps} = playbook} when is_list(steps) ->
        Logger.info("[Transcriber] Generated playbook with #{length(steps)} steps")
        {:ok, playbook}

      {:ok, _} ->
        Logger.warning("[Transcriber] Response had no `steps` key. Raw: #{String.slice(text, 0, 500)}")
        {:error, :missing_steps_key}

      {:error, reason} ->
        Logger.warning(
          "[Transcriber] Failed to parse JSON: #{inspect(reason)}. Raw response: #{String.slice(text, 0, 1000)}"
        )

        {:error, {:json_parse, reason, text}}
    end
  end

  defp clean_json(text) do
    text
    |> String.replace(~r/```json\s*/, "")
    |> String.replace(~r/```\s*/, "")
    |> String.trim()
    |> extract_json_object()
  end

  defp extract_json_object(text) do
    case Regex.run(~r/\{.*\}/s, text) do
      [match] -> match
      _ -> text
    end
  end
end
