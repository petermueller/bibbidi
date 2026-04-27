defmodule Autopilot.Tools.Done do
  @moduledoc "Task completion tool — signals task done or asks user for confirmation."

  alias LangChain.Function
  alias LangChain.FunctionParam

  def task_complete do
    Function.new!(%{
      name: "task_complete",
      description: """
      Call this when the task is fully completed OR when you are unsure if done.
      Always call this to end the session — never just stop calling tools.
      If unsure, set needs_confirmation to true and the user will decide.
      """,
      parameters: [
        FunctionParam.new!(%{name: "summary", type: :string, required: true,
          description: "Summary of what was accomplished"}),
        FunctionParam.new!(%{name: "needs_confirmation", type: :boolean, required: false,
          description: "Set true if unsure the task is complete and need user input"})
      ],
      function: fn args, _context ->
        summary            = args["summary"]
        needs_confirmation = args["needs_confirmation"] || false

        if needs_confirmation do
          IO.puts("\n")
          IO.puts("+-----------------------------------------+")
          IO.puts("|         AGENT NEEDS CONFIRMATION        |")
          IO.puts("+-----------------------------------------+")
          IO.puts("| #{String.pad_trailing(summary, 39)}|")
          IO.puts("+-----------------------------------------+")

          answer =
            IO.gets("Is the task complete? (yes / no / continue with instructions): ")
            |> String.trim()
            |> String.downcase()

          cond do
            answer == "yes" ->
              {:ok, "TASK_DONE: #{summary}"}

            answer == "no" ->
              {:ok, "TASK_NOT_DONE: User says task is not complete. Please continue."}

            String.length(answer) > 0 ->
              {:ok, "TASK_CONTINUE: User says: #{answer}. Please continue accordingly."}

            true ->
              {:ok, "TASK_DONE: #{summary}"}
          end
        else
          {:ok, "TASK_DONE: #{summary}"}
        end
      end
    })
  end
end
