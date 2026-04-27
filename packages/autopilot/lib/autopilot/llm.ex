defmodule Autopilot.Llm do
  @moduledoc "Creates LangChain LLM instances for each agent node."

  alias LangChain.ChatModels.{ChatAnthropic, ChatOllamaAI, ChatOpenAI}

  @type node_name :: :planner | :validator | :narrator

  @spec for_node(node_name()) :: struct()
  def for_node(node) do
    cfg = Application.get_env(:autopilot, node, %{})
    build(cfg[:provider] || "anthropic", cfg[:model], cfg[:temperature] || 0)
  end

  # --- Private ---

  defp build("anthropic", model, temperature) do
    ChatAnthropic.new!(%{
      model:       model || "claude-sonnet-4-5-20250929",
      temperature: temperature,
      api_key:     api_key!(:anthropic_api_key, "ANTHROPIC_API_KEY")
    })
  end

  defp build("ollama", model, temperature) do
    ChatOllamaAI.new!(%{
      model:       model || "llama3.2",
      temperature: temperature,
      endpoint:    Application.get_env(:autopilot, :ollama_base_url, "http://localhost:11434")
                   |> URI.merge("/api/chat")
                   |> URI.to_string()
    })
  end

  defp build("ollama_cloud", model, temperature) do
    base = Application.get_env(:autopilot, :ollama_cloud_url) ||
             raise "OLLAMA_CLOUD_URL not configured"

    ChatOpenAI.new!(%{
      model:       model || "ministral-3:14b",
      temperature: temperature,
      endpoint:    URI.merge(base, "/v1/chat/completions") |> URI.to_string(),
      api_key:     api_key!(:ollama_api_key, "OLLAMA_API_KEY")
    })
  end

  defp build(provider, _model, _temperature) do
    raise "Unknown LLM provider: #{provider}"
  end

  defp api_key!(config_key, env_var) do
    Application.get_env(:autopilot, config_key) ||
      System.get_env(env_var) ||
      raise "#{env_var} not set"
  end
end
