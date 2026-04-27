defmodule Playbook do
  @moduledoc """
  Browser session recorder and playbook generator.

  Records user interactions with a browser (clicks, inputs, navigation)
  and transcribes the session log into a structured playbook JSON using
  an LLM.

  Uses two LLM roles:
    - Router:      Sagents agent that interprets user commands via tools
    - Transcriber: analyzes the full session log and produces the
                   structured playbook JSON

  ## Usage

      iex -S mix
      Playbook.start()
  """

  def start do
    Playbook.CLI.start()
  end
end
