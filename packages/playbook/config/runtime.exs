import Config
import Dotenvy

source!([Path.join([__DIR__, "..", ".env"]) |> Path.expand(), System.get_env()])

IO.puts(">> Config loaded - provider: #{System.get_env("ROUTER_PROVIDER", "ollama")}")

config :playbook,
  # Recorder
  poll_interval_ms: env!("POLL_INTERVAL_MS", :integer, 1000),
  playbook_output_dir: env!("PLAYBOOK_OUTPUT_DIR", :string, "./playbooks"),

  # LLM providers
  anthropic_api_key: env!("ANTHROPIC_API_KEY", :string, nil),
  ollama_url:        env!("OLLAMA_URL",        :string, "http://localhost:11434"),
  ollama_cloud_url:  env!("OLLAMA_CLOUD_URL",  :string, nil),
  ollama_api_key:    env!("OLLAMA_API_KEY",    :string, nil),

  # Router LLM (lightweight — interprets user commands)
  router: %{
    provider:    env!("ROUTER_PROVIDER",    :string, "ollama"),
    model:       env!("ROUTER_MODEL",       :string, "llama3.2"),
    temperature: env!("ROUTER_TEMPERATURE", :float,  0.0)
  },

  # Transcriber LLM (analyzes full session log → playbook JSON)
  transcriber: %{
    provider:    env!("TRANSCRIBER_PROVIDER",    :string, "ollama"),
    model:       env!("TRANSCRIBER_MODEL",       :string, "devstral-small-2:24b"),
    temperature: env!("TRANSCRIBER_TEMPERATURE", :float,  0.0)
  },

  # 1Password (optional — for vault variable source)
  op_service_account_token: env!("OP_SERVICE_ACCOUNT_TOKEN", :string, nil)

# Configure Autopilot (browser + agent)
config :autopilot,
  # Browser
  browser:          env!("BROWSER",          :string, "firefox"),
  firefox_ws_url:   env!("FIREFOX_WS_URL",   :string, "ws://localhost:9222/session"),
  chromedriver_url: env!("CHROMEDRIVER_URL",  :string, "http://localhost:9515"),

  # Vision API
  vision_url: env!("VISION_URL", :string, "http://localhost:5001"),

  # Observability
  observer: [enabled: true],
  context_pruner: [enabled: true, keep_turns: 3],

  # LLM providers (shared with playbook)
  anthropic_api_key: env!("ANTHROPIC_API_KEY", :string, nil),
  ollama_base_url:   env!("OLLAMA_URL",        :string, "http://localhost:11434"),
  ollama_cloud_url:  env!("OLLAMA_CLOUD_URL",  :string, nil),
  ollama_api_key:    env!("OLLAMA_API_KEY",    :string, nil),

  # Planner LLM (for autopilot agent steps)
  planner: %{
    provider:    env!("PLANNER_PROVIDER",    :string, "anthropic"),
    model:       env!("PLANNER_MODEL",       :string, "claude-sonnet-4-5-20250929"),
    temperature: env!("PLANNER_TEMPERATURE", :float,  0.0)
  }
