defmodule Playbook.Tools.Transcribe do
  @moduledoc "Transcription tool: stops recording and generates playbook JSON."

  alias LangChain.Function

  def generate_playbook do
    Function.new!(%{
      name: "generate_playbook",
      description: """
      Stop recording, analyze the full session log, and generate a structured
      playbook JSON. The transcriber LLM will infer the goal, discard noise,
      identify conditional steps, and produce clean automation steps.
      May ask the user clarifying questions before generating.
      """,
      parameters: [],
      function: fn _args, _context ->
        llm_fn = Playbook.Llm.for_fn(:transcriber)

        case Playbook.Recorder.end_session() do
          {:ok, name, log} ->
            if length(log) == 0 do
              {:error, "No events were recorded."}
            else
              case Playbook.Transcriber.generate(name, log, llm_fn) do
                {:ok, playbook} ->
                  steps = playbook["steps"] || []

                  summary = steps
                    |> Enum.with_index(1)
                    |> Enum.map(fn {step, i} ->
                      cond_str = if step["condition"], do: " [if #{step["condition"]}]", else: ""
                      human_str = if step["human"], do: " (human)", else: ""
                      "#{i}. [#{step["action"]}] #{step["label"]}#{cond_str}#{human_str}"
                    end)
                    |> Enum.join("\n")

                  # Store for save_playbook to access
                  Playbook.State.set_playbook(playbook)

                  {:ok, """
                  Playbook generated: "#{playbook["name"]}"
                  Goal: #{playbook["goal"]}
                  Steps (#{length(steps)}):
                  #{summary}

                  Say 'save' to save it.
                  """}

                {:error, reason} ->
                  {:error, "Generation failed: #{inspect(reason)}"}
              end
            end

          {:error, :not_recording} ->
            {:error, "Not currently recording."}
        end
      end
    })
  end
end
