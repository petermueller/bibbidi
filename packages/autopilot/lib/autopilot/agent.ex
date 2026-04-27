defmodule Autopilot.Agent do
  @moduledoc "Browser automation agent — single LLM loop with middleware hooks."

  alias Sagents.{Agent, AgentServer, State}
  alias LangChain.Message

  def run(task) do
    agent_id = "autopilot-#{:os.system_time(:millisecond)}"

    {:ok, agent} = Agent.new(%{
      agent_id: agent_id,
      model:    Autopilot.Llm.for_node(:planner),
      base_system_prompt: "",
      middleware: [
        Autopilot.Middleware.Planner,
        Autopilot.Middleware.ContextPruner,
        Autopilot.Middleware.Observer
      ]
    })

    state = State.new!(%{messages: [Message.new_user!(task)]})

    {:ok, _pid} = AgentServer.start_link(
      agent:              agent,
      initial_state:      state,
      pubsub:             {Phoenix.PubSub, :autopilot_pubsub},
      inactivity_timeout: 300_000
    )

    AgentServer.subscribe(agent_id)
    :ok = AgentServer.execute(agent_id)

    await(agent_id)
  end

  defp await(agent_id) do
    receive do
      {:agent, {:llm_deltas, deltas}} ->
        Enum.each(deltas, fn d -> IO.write(d.content || "") end)
        await(agent_id)

      {:agent, {:llm_message, message}} ->
        content = case message.content do
          text when is_binary(text) -> text
          parts when is_list(parts) ->
            parts |> Enum.map(fn p -> Map.get(p, :content, "") end) |> Enum.join("")
          _ -> ""
        end
        if String.trim(content) != "" do
          IO.puts("\n\n[AGENT REASONING] #{String.trim(content)}")
        end
        await(agent_id)

      {:agent, {:tool_call_identified, tool_info}} ->
        args = tool_info |> Map.get(:arguments, %{}) |> Map.drop(["screenshot"])
        IO.puts("\n[DECISION] → #{tool_info.name} #{inspect(args)}")
        await(agent_id)

      {:agent, {:tool_execution_completed, _id, result}} ->
        content = get_in(result, [:content]) || ""
        IO.puts("\n[RESULT] #{String.slice(to_string(content), 0, 200)}")

        if String.starts_with?(to_string(content), "TASK_DONE") do
          IO.puts("\n\n✓ Task complete: #{content}")
          :ok
        else
          await(agent_id)
        end

      {:agent, {:tool_execution_failed, _id, error}} ->
        IO.puts("\n[FAILED] #{inspect(error)}")
        await(agent_id)

      {:agent, {:status_changed, :idle, _}} ->
        IO.puts("\n\nAgent finished.")
        :ok

      {:agent, {:status_changed, :error, reason}} ->
        IO.puts("\n\nError: #{inspect(reason)}")
        {:error, reason}

      {:agent, {:status_changed, status, _}} ->
        IO.puts("\n[STATUS] #{status}")
        await(agent_id)

      {:agent, _} ->
        await(agent_id)

    after 120_000 ->
      IO.puts("\n\nTimeout.")
      {:error, :timeout}
    end
  end
end

defmodule Autopilot.CLI do
  def start do
    IO.puts("""
    +==================================+
    |    Autopilot Browser Agent       |
    +==================================+
    Type your task and press Enter.
    Type 'exit' to quit.
    """)

    Autopilot.Browser.start_link()

    IO.puts("""
    +==================================+
    ...
    """)

    loop()
  end

  defp loop do
    case IO.gets("\n> Task: ") |> String.trim() do
      "exit" -> IO.puts("Goodbye!")
      ""     -> loop()
      task   ->
        IO.puts("\nStarting agent...\n")
        Autopilot.Agent.run(task)
        loop()
    end
  end
end
