defmodule Playbook.Llm do
  @moduledoc """
  Creates LLM instances for playbook nodes.

  - for_node/1: returns a LangChain ChatModel struct (for Sagents agent)
  - for_fn/1:   returns a simple function (system, user) -> {:ok, response}
                (for the transcriber, which doesn't use Sagents)
  """

  alias LangChain.ChatModels.{ChatAnthropic, ChatOllamaAI, ChatOpenAI}

  @type node_name :: :router | :transcriber

  # ── ChatModel for Sagents ──────────────────────────────────────

  @spec for_node(node_name()) :: struct()
  def for_node(node) do
    cfg = Application.get_env(:playbook, node, %{})
    build_model(cfg[:provider] || "ollama", cfg[:model], cfg[:temperature] || 0.0)
  end

  defp build_model("anthropic", model, temperature) do
    ChatAnthropic.new!(%{
      model:       model || "claude-sonnet-4-5-20250929",
      temperature: temperature,
      api_key:     api_key!(:anthropic_api_key, "ANTHROPIC_API_KEY")
    })
  end

  defp build_model("ollama", model, temperature) do
    ChatOllamaAI.new!(%{
      model:       model || "llama3.2",
      temperature: temperature,
      endpoint:    Application.get_env(:playbook, :ollama_url, "http://localhost:11434")
                   |> URI.merge("/api/chat")
                   |> URI.to_string()
    })
  end

  defp build_model("ollama_cloud", model, temperature) do
    base = Application.get_env(:playbook, :ollama_cloud_url) ||
             raise "OLLAMA_CLOUD_URL not configured"

    ChatOpenAI.new!(%{
      model:       model || "devstral-small-2:24b",
      temperature: temperature,
      endpoint:    URI.merge(base, "/v1/chat/completions") |> URI.to_string(),
      api_key:     api_key!(:ollama_api_key, "OLLAMA_API_KEY")
    })
  end

  defp build_model(provider, _model, _temperature) do
    raise "Unknown LLM provider: #{provider}"
  end

  # ── Simple function for Transcriber ────────────────────────────

  @spec for_fn(node_name()) :: (String.t(), String.t() -> {:ok, String.t()} | {:error, term()})
  def for_fn(node) do
    cfg = Application.get_env(:playbook, node, %{})
    build_fn(cfg[:provider] || "ollama", cfg[:model], cfg[:temperature] || 0.0)
  end

  defp build_fn("anthropic", model, temperature) do
    model = model || "claude-sonnet-4-5-20250929"
    api_key = api_key!(:anthropic_api_key, "ANTHROPIC_API_KEY")

    fn system, user ->
      case Req.post("https://api.anthropic.com/v1/messages",
        json: %{
          model: model,
          max_tokens: 4096,
          temperature: temperature,
          system: system,
          messages: [%{role: "user", content: user}]
        },
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", "2023-06-01"}
        ],
        receive_timeout: 120_000
      ) do
        {:ok, %{body: %{"content" => [%{"text" => text} | _]}}} -> {:ok, text}
        {:ok, %{status: status, body: body}} -> {:error, "Anthropic #{status}: #{inspect(body)}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_fn("ollama", model, temperature) do
    model = model || "devstral-small-2:24b"
    base_url = Application.get_env(:playbook, :ollama_url, "http://localhost:11434")

    fn system, user ->
      case Req.post("#{base_url}/api/chat",
        json: %{
          model: model,
          messages: [
            %{role: "system", content: system},
            %{role: "user", content: user}
          ],
          stream: false,
          options: %{temperature: temperature}
        },
        receive_timeout: 120_000
      ) do
        {:ok, %{body: %{"message" => %{"content" => content}}}} -> {:ok, content}
        {:ok, %{status: status}} -> {:error, "Ollama #{status}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_fn("ollama_cloud", model, temperature) do
    model = model || "devstral-small-2:24b"
    base_url = Application.get_env(:playbook, :ollama_cloud_url) ||
               raise "OLLAMA_CLOUD_URL not configured"
    api_key = api_key!(:ollama_api_key, "OLLAMA_API_KEY")

    fn system, user ->
      case Req.post("#{base_url}/v1/chat/completions",
        json: %{
          model: model,
          temperature: temperature,
          messages: [
            %{role: "system", content: system},
            %{role: "user", content: user}
          ]
        },
        headers: [{"Authorization", "Bearer #{api_key}"}],
        receive_timeout: 120_000
      ) do
        {:ok, %{body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} -> {:ok, content}
        {:ok, %{status: status}} -> {:error, "Ollama cloud #{status}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_fn(provider, _model, _temperature) do
    raise "Unknown LLM provider: #{provider}"
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp api_key!(config_key, env_var) do
    Application.get_env(:playbook, config_key) ||
      System.get_env(env_var) ||
      raise "#{env_var} not set"
  end
end
