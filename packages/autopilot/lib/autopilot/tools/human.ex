defmodule Autopilot.Tools.Human do
  @moduledoc """
  Human input tool — pauses execution for sensitive input (passwords, MFA).
  The value is typed DIRECTLY into the browser and NEVER sent to the LLM.
  """

  alias LangChain.Function
  alias LangChain.FunctionParam

  def human_input do
    Function.new!(%{
      name: "human_input",
      description: """
      Ask the human to provide sensitive input like passwords or MFA codes.
      Input goes directly to the browser — NEVER returned to the AI.
      Use for ANY sensitive credentials — never ask for passwords in chat.
      """,
      parameters: [
        FunctionParam.new!(%{name: "instruction", type: :string, required: true,
          description: "What to ask the human, e.g. 'Please enter your password'"}),
        FunctionParam.new!(%{name: "selector", type: :string, required: true,
          description: "CSS selector of the field, e.g. '#login-pwd'"})
      ],
      function: fn %{"instruction" => instruction, "selector" => selector}, _context ->
        IO.puts("\n")
        IO.puts("+-----------------------------------------+")
        IO.puts("|         HUMAN INPUT REQUIRED            |")
        IO.puts("+-----------------------------------------+")
        IO.puts("| #{instruction}")
        IO.puts("| Field: #{selector}")
        IO.puts("+-----------------------------------------+")
        IO.puts("| Note: input is visible while typing     |")
        IO.puts("+-----------------------------------------+")

        # :io.get_line works across processes (unlike :io.get_password)
        value =
          :io.get_line("Enter value: ")
          |> to_string()
          |> String.trim()

        case Autopilot.Browser.type(selector, value) do
          {:ok, _} ->
            IO.puts("Input entered.\n")
            {:ok, "Human input entered into '#{selector}' successfully."}

          {:error, reason} ->
            {:error, "Failed to enter input into '#{selector}': #{inspect(reason)}"}
        end
      end
    })
  end
end
