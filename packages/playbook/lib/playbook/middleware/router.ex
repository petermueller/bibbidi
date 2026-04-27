defmodule Playbook.Middleware.Router do
  @moduledoc "Router middleware — system prompt + playbook tools."
  @behaviour Sagents.Middleware

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def system_prompt(_config) do
    """
    You are a playbook recorder assistant. You help users record browser
    interactions and generate structured playbooks for RPA automation.

    ## What you do:
    - Start/stop recording sessions
    - Accept context notes from the user about what they're doing
    - Show the current recording log
    - Generate structured playbook JSON from the session log
    - Save and load playbooks
    - Execute saved playbooks

    ## Workflow:
    1. User says something like "start recording the login flow"
       → call start_recording with the session name
    2. User interacts with the browser (events are captured automatically)
    3. User provides context like "this popup is conditional" or
       "the password comes from uhc.txt in the passwords folder"
       → call annotate with their text
    4. User says "generate" or "done"
       → call generate_playbook
    5. User says "save" or "save it"
       → call save_playbook
    6. User says "run the login playbook"
       → call run_playbook

    ## Rules:
    - One tool call per turn.
    - When the user provides context about what they're doing while recording,
      ALWAYS call annotate. These notes are critical for the transcriber.
    - Respond in the user's language.
    - Keep responses short and helpful.
    - If the user just says hi, respond conversationally — no tool call needed.
    """
  end

  @impl true
  def tools(_config) do
    [
      Playbook.Tools.Session.start_recording(),
      Playbook.Tools.Session.stop_recording(),
      Playbook.Tools.Session.annotate(),
      Playbook.Tools.Session.peek(),
      Playbook.Tools.Transcribe.generate_playbook(),
      Playbook.Tools.Persistence.save_playbook(),
      Playbook.Tools.Persistence.load_playbook(),
      Playbook.Tools.Persistence.run_playbook()
    ]
  end

  @impl true
  def before_model(state, _config), do: {:ok, state}

  @impl true
  def after_model(state, _config), do: {:ok, state}

  @impl true
  def handle_message(_msg, state, _config), do: {:ok, state}

  @impl true
  def on_server_start(state, _config), do: {:ok, state}
end
