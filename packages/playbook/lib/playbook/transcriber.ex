defmodule Playbook.Transcriber do
  @moduledoc """
  Converts a raw session log into a structured playbook JSON.

  Takes the full text log from the Recorder, sends it to an LLM
  with instructions to analyze the session, infer the goal, discard
  noise, and produce a clean playbook with proper step types.

  The transcriber is conversational — it can ask the user questions
  if something is ambiguous before generating the final JSON.

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
  This keeps the transformer independent of any specific LLM library.

  Options:
    - :interactive - if true, asks user for clarification via IO (default: true)
    - :max_questions - max clarification rounds (default: 3)
  """
  @spec generate(String.t(), [LogEntry.t()], llm_fn(), keyword()) ::
    {:ok, map()} | {:error, term()}
  def generate(session_name, log, llm_fn, opts \\ []) do
    interactive = Keyword.get(opts, :interactive, true)
    max_questions = Keyword.get(opts, :max_questions, 3)

    log_text = format_log(log)
    system = system_prompt()
    user_msg = initial_prompt(session_name, log_text)

    Logger.info("[Transcriber] Analyzing #{length(log)} events for \"#{session_name}\"")

    case llm_fn.(system, user_msg) do
      {:ok, response} ->
        handle_response(response, system, llm_fn, interactive, max_questions, 0)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Response handling ──────────────────────────────────────────

  defp handle_response(response, system, llm_fn, interactive, max_questions, question_count) do
    cond do
      # LLM produced valid JSON — done
      json_playbook?(response) ->
        parse_playbook(response)

      # LLM is asking a question and we can interact
      interactive && question_count < max_questions ->
        IO.puts("\n[Transcriber] #{response}")
        answer = IO.gets("\n> Answer: ") |> String.trim()

        if answer == "" || answer == "skip" do
          # Re-prompt asking for best guess
          followup = "The user skipped this question. Use your best judgment and generate the playbook JSON now."
          case llm_fn.(system, followup) do
            {:ok, new_response} ->
              handle_response(new_response, system, llm_fn, interactive, max_questions, question_count + 1)
            {:error, reason} ->
              {:error, reason}
          end
        else
          case llm_fn.(system, answer) do
            {:ok, new_response} ->
              handle_response(new_response, system, llm_fn, interactive, max_questions, question_count + 1)
            {:error, reason} ->
              {:error, reason}
          end
        end

      # Non-interactive or max questions reached — force JSON
      true ->
        force_msg = "Generate the playbook JSON now. Output ONLY the JSON, no explanation."
        case llm_fn.(system, force_msg) do
          {:ok, new_response} -> parse_playbook(new_response)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # ── Prompt construction ────────────────────────────────────────

  defp system_prompt do
    """
    You are a Playbook Transformer. You analyze a raw browser session log
    and convert it into a clean, structured playbook JSON.

    YOUR RESPONSIBILITIES:
    1. Infer the overall GOAL of the session from the sequence of actions
    2. DISCARD noise: accidental clicks, scrolls that led nowhere, repeated actions
    3. Identify which steps are CONDITIONAL (popups, 2FA, optional dialogs)
    4. Identify which steps need HUMAN INPUT (passwords, MFA codes, CAPTCHAs)
    5. Convert sensitive values to template variables: {{username}}, {{password}}, {{mfa_code}}
    6. Generate clean CSS selectors — prefer #id > [name=x] > tag.class
    7. Add clear labels to each step

    STEP TYPES:
    - goto:        Navigate to a URL
    - click:       Click an element by selector
    - type:        Type text into an input
    - press_key:   Press a keyboard key (Enter, Tab, etc.)
    - wait_url:    Wait for URL to contain a string (after redirects)
    - wait_element: Wait for an element to appear
    - assert_url:  Verify current URL (fail if wrong)
    - human:       Pause for human action (password, MFA, CAPTCHA)

    STEP PROPERTIES:
    - action:     (required) step type from above
    - selector:   CSS selector for the target element
    - value:      text to type or URL to navigate to
    - label:      human-readable description of the step
    - condition:  "element_visible" | "url_contains" | "text_on_page" (makes step conditional)
    - condition_value: the selector/url/text to check for the condition
    - human:      true if this step requires human interaction
    - variable:   template variable name like "username" (replaces hardcoded value)

    OUTPUT FORMAT:
    {
      "name": "Session Name",
      "goal": "What this playbook accomplishes",
      "steps": [
        {"action": "goto", "value": "https://...", "label": "Open login page"},
        {"action": "type", "selector": "#email", "variable": "username", "label": "Enter username"},
        {"action": "type", "selector": "#password", "variable": "password", "human": true, "label": "Enter password"},
        {"action": "click", "selector": "button[type=submit]", "label": "Submit login form"},
        {"action": "wait_url", "value": "dashboard", "label": "Wait for dashboard"},
        {"action": "click", "selector": ".cookie-accept", "label": "Accept cookies", "condition": "element_visible", "condition_value": ".cookie-accept"}
      ]
    }

    RULES:
    - If something is unclear, ASK the user before generating. Keep questions short and specific.
    - If the user provides annotations ([NOTE] entries), use them as context for your decisions.
    - Password fields are ALWAYS human steps with {{password}} variable.
    - Login-related inputs should use template variables.
    - Output ONLY valid JSON when generating the playbook. No markdown, no explanation.
    - Prefer fewer, cleaner steps over many granular ones.
    """
  end

  defp initial_prompt(session_name, log_text) do
    """
    Session: "#{session_name}"

    RAW SESSION LOG:
    #{log_text}

    Analyze this session log. If anything is unclear or ambiguous, ask me
    a specific question. Otherwise, generate the playbook JSON.
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

  defp json_playbook?(text) do
    cleaned = clean_json(text)
    case Jason.decode(cleaned) do
      {:ok, %{"steps" => steps}} when is_list(steps) -> true
      _ -> false
    end
  end

  defp parse_playbook(text) do
    cleaned = clean_json(text)
    case Jason.decode(cleaned) do
      {:ok, %{"steps" => _} = playbook} ->
        Logger.info("[Transcriber] Generated playbook with #{length(playbook["steps"])} steps")
        {:ok, playbook}

      {:ok, _} ->
        {:error, :missing_steps_key}

      {:error, reason} ->
        Logger.warning("[Transcriber] Failed to parse JSON: #{inspect(reason)}")
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
