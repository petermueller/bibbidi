defmodule Playbook.Agent do
  @moduledoc "Playbook agent — Sagents loop with middleware hooks."

  alias Sagents.{Agent, AgentServer, State}
  alias LangChain.Message

  def run(input) do
    agent_id = "playbook-#{:os.system_time(:millisecond)}"

    {:ok, agent} = Agent.new(%{
      agent_id: agent_id,
      model:    Playbook.Llm.for_node(:router),
      base_system_prompt: "",
      middleware: [
        Playbook.Middleware.Router
      ]
    })

    state = State.new!(%{messages: [Message.new_user!(input)]})

    {:ok, _pid} = AgentServer.start_link(
      agent:              agent,
      initial_state:      state,
      pubsub:             {Phoenix.PubSub, :playbook_pubsub},
      inactivity_timeout: 120_000
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
          IO.puts("\n#{String.trim(content)}")
        end
        await(agent_id)

      {:agent, {:tool_call_identified, tool_info}} ->
        args = tool_info |> Map.get(:arguments, %{})
        IO.puts("\n[TOOL] → #{tool_info.name} #{inspect(args)}")
        await(agent_id)

      {:agent, {:tool_execution_completed, _id, result}} ->
        content = get_in(result, [:content]) || ""
        IO.puts("[RESULT] #{String.slice(to_string(content), 0, 300)}")
        await(agent_id)

      {:agent, {:tool_execution_failed, _id, error}} ->
        IO.puts("\n[FAILED] #{inspect(error)}")
        await(agent_id)

      {:agent, {:status_changed, :idle, _}} ->
        :ok

      {:agent, {:status_changed, :error, reason}} ->
        IO.puts("\nError: #{inspect(reason)}")
        {:error, reason}

      {:agent, {:status_changed, _status, _}} ->
        await(agent_id)

      {:agent, _} ->
        await(agent_id)

    after 120_000 ->
      IO.puts("\nTimeout.")
      {:error, :timeout}
    end
  end
end

defmodule Playbook.CLI do
  def start do
    IO.puts("""
    +==================================+
    |    Playbook Recorder             |
    +==================================+
    Talk naturally. The agent handles everything.

    Start Firefox first:
      firefox --remote-debugging-port=9222
    """)

    # Start Autopilot.Browser for shared browser access
    case Autopilot.Browser.start_link() do
      {:ok, _} -> IO.puts("  ✅ Browser connected")
      {:error, reason} -> IO.puts("  ❌ Browser: #{inspect(reason)}")
    end

    # Start the Recorder
    case Playbook.Recorder.start_link() do
      {:ok, _} -> IO.puts("  ✅ Recorder ready\n")
      {:error, reason} -> IO.puts("  ❌ Recorder: #{inspect(reason)}\n")
    end

    loop()
  end

  defp loop do
    recording = Playbook.Recorder.recording?()
    prompt = if recording, do: "\n[REC] > ", else: "\n> "

    case IO.gets(prompt) |> String.trim() do
      "exit" -> IO.puts("Goodbye!")
      ""     -> loop()
      input  ->
        Playbook.Agent.run(input)
        loop()
    end
  end
end
