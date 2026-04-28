defmodule Playbook.Runner do
  @moduledoc """
  Executes a playbook JSON step by step using Autopilot.Browser
  for browser control and Autopilot.Agent for autonomous steps.

  ## Usage

      {:ok, playbook} = Playbook.load("playbooks/uhc_login.json")
      Playbook.Runner.execute(playbook)
  """

  require Logger

  @passwords_dir "passwords"

  # ── Public API ─────────────────────────────────────────────────

  @doc "Execute a playbook from a map."
  def execute(playbook) when is_map(playbook) do
    name = playbook["name"] || "Untitled"
    steps = playbook["steps"] || []
    variables = playbook["variables"] || %{}

    Logger.info("[Runner] Starting playbook: \"#{name}\" (#{length(steps)} steps)")

    # Resolve all variables before execution
    resolved = resolve_variables(variables)

    # Execute steps sequentially
    result = run_steps(steps, resolved, 1)

    case result do
      :ok ->
        Logger.info("[Runner] Playbook \"#{name}\" completed successfully")
        :ok

      {:error, step_num, reason} ->
        Logger.error("[Runner] Playbook \"#{name}\" failed at step #{step_num}: #{inspect(reason)}")
        {:error, step_num, reason}
    end
  end

  @doc "Execute a playbook from a JSON file path."
  def execute_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, playbook} -> execute(playbook)
          {:error, reason} -> {:error, 0, reason}
        end
      {:error, reason} -> {:error, 0, reason}
    end
  end

  # ── Variable resolution ────────────────────────────────────────

  defp resolve_variables(variables) do
    Enum.reduce(variables, %{}, fn {name, config}, acc ->
      value = resolve_variable(name, config)
      Map.put(acc, name, value)
    end)
  end

  defp resolve_variable(name, config) when is_map(config) do
    source = config["source"] || "human"
    sensitive = sensitive?(config)

    case source do
      "human" ->
        description = config["description"] || name
        value = if sensitive do
          read_secret("  👤 Enter #{description}: ")
        else
          IO.gets("  👤 Enter #{description}: ") |> String.trim()
        end
        Logger.info("[Runner] Variable \"#{name}\" provided by user")
        value

      "file" ->
        path = config["path"]
        value = File.read!(path) |> String.trim()
        Logger.info("[Runner] Variable \"#{name}\" loaded from file")
        value

      "password" ->
        filename = config["filename"]
        path = Path.join(@passwords_dir, filename)

        if File.exists?(path) do
          value = File.read!(path) |> String.trim()
          Logger.info("[Runner] Variable \"#{name}\" loaded from passwords/")
          value
        else
          Logger.warning("[Runner] Password file not found: #{path}")
          read_secret("  👤 Password file not found. Enter #{name}: ")
        end

      "env" ->
        key = config["key"] || String.upcase(name)
        case System.get_env(key) do
          nil ->
            Logger.warning("[Runner] Env var #{key} not set")
            value = if sensitive do
              read_secret("  👤 Env var #{key} not set. Enter #{name}: ")
            else
              IO.gets("  👤 Env var #{key} not set. Enter #{name}: ") |> String.trim()
            end
            value
          value ->
            Logger.info("[Runner] Variable \"#{name}\" loaded from env")
            value
        end

      "vault" ->
        key = config["key"]
        op_env = case Application.get_env(:playbook, :op_service_account_token) do
          nil -> []
          token -> [{"OP_SERVICE_ACCOUNT_TOKEN", token}]
        end

        case System.cmd("op", ["read", "op://#{key}"], env: op_env, stderr_to_stdout: true) do
          {value, 0} ->
            Logger.info("[Runner] Variable \"#{name}\" loaded from 1Password")
            String.trim(value)
          {error, _} ->
            Logger.warning("[Runner] 1Password read failed for \"#{name}\": #{String.trim(error)}")
            read_secret("  👤 Vault read failed. Enter #{name}: ")
        end

      other ->
        Logger.warning("[Runner] Unknown source \"#{other}\" for variable \"#{name}\"")
        IO.gets("  👤 Enter #{name}: ") |> String.trim()
    end
  end

  defp resolve_variable(_name, value) when is_binary(value), do: value

  defp sensitive?(%{"source" => "password"}), do: true
  defp sensitive?(%{"source" => "vault"}), do: true
  defp sensitive?(%{"sensitive" => true}), do: true
  defp sensitive?(_), do: false

  defp read_secret(prompt) do
    IO.write(prompt)
    port = Port.open({:spawn, "stty -echo"}, [:binary])
    Port.close(port)
    value = IO.gets("") |> String.trim()
    port = Port.open({:spawn, "stty echo"}, [:binary])
    Port.close(port)
    IO.puts("")
    value
  end

  # ── Step execution ─────────────────────────────────────────────

  defp run_steps([], _vars, _n), do: :ok

  defp run_steps([step | rest], vars, n) do
    label = step["label"] || "Step #{n}"

    if should_run?(step) do
      Logger.info("[Runner] Step #{n}: #{label}")
      IO.puts("  ▶ #{n}. #{label}")

      case execute_step(step, vars) do
        :ok ->
          run_steps(rest, vars, n + 1)

        {:error, reason} ->
          IO.puts("  ❌ Step #{n} failed: #{inspect(reason)}")
          {:error, n, reason}
      end
    else
      Logger.info("[Runner] Step #{n}: #{label} (skipped)")
      IO.puts("  ⏭ #{n}. #{label} (skipped)")
      run_steps(rest, vars, n + 1)
    end
  end

  # ── Condition checking ─────────────────────────────────────────

  defp should_run?(%{"condition" => nil}), do: true
  defp should_run?(%{"condition" => condition} = step) do
    value = step["condition_value"] || ""

    case condition do
      "element_visible" ->
        element_visible?(value)

      "element_not_visible" ->
        not element_visible?(value)

      "url_contains" ->
        {:ok, url} = get_url()
        String.contains?(url, value)

      "url_not_contains" ->
        {:ok, url} = get_url()
        not String.contains?(url, value)

      "text_on_page" ->
        {:ok, text} = get_page_text()
        String.contains?(text, value)

      "text_not_on_page" ->
        {:ok, text} = get_page_text()
        not String.contains?(text, value)

      _ ->
        Logger.warning("[Runner] Unknown condition: #{condition}")
        true
    end
  end

  defp should_run?(_step), do: true

  # ── Step dispatch ──────────────────────────────────────────────

  defp execute_step(%{"action" => "goto"} = step, _vars) do
    url = step["value"]
    case Autopilot.Browser.navigate(url) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_step(%{"action" => "click"} = step, _vars) do
    selector = step["selector"]
    js = """
    (function() {
      var el = document.querySelector('#{escape_js(selector)}');
      if (!el) return JSON.stringify({error: 'not_found'});
      var rect = el.getBoundingClientRect();
      return JSON.stringify({x: Math.round(rect.x + rect.width/2), y: Math.round(rect.y + rect.height/2)});
    })()
    """
    case Autopilot.Browser.eval(js) do
      {:ok, result} ->
        case Jason.decode(result) do
          {:ok, %{"x" => x, "y" => y}} ->
            Autopilot.Browser.click(x, y)
            :ok
          {:ok, %{"error" => _}} ->
            {:error, "Element not found: #{selector}"}
          _ ->
            {:error, "Could not locate element: #{selector}"}
        end
      error -> {:error, error}
    end
  end

  defp execute_step(%{"action" => "type"} = step, vars) do
    selector = step["selector"]
    value = resolve_step_value(step, vars)
    case Autopilot.Browser.type(selector, value) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_step(%{"action" => "press_key"} = step, _vars) do
    key = step["value"] || "Enter"
    case Autopilot.Browser.press_key(key) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_step(%{"action" => "scroll"} = step, _vars) do
    direction = step["direction"] || "down"
    amount = step["amount"] || 400
    case Autopilot.Browser.scroll(direction, amount) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_step(%{"action" => "wait_element"} = step, _vars) do
    selector = step["selector"]
    timeout = step["timeout"] || 10_000
    wait_for_element(selector, timeout)
  end

  defp execute_step(%{"action" => "wait_url"} = step, _vars) do
    value = step["value"]
    timeout = step["timeout"] || 10_000
    wait_for_url_contains(value, timeout)
  end

  defp execute_step(%{"action" => "assert_url"} = step, _vars) do
    expected = step["value"]
    {:ok, url} = get_url()

    if String.contains?(url, expected) do
      :ok
    else
      {:error, "URL assertion failed: expected \"#{expected}\" in \"#{url}\""}
    end
  end

  defp execute_step(%{"action" => "autopilot"} = step, _vars) do
    prompt = step["prompt"]
    IO.puts("  🤖 Delegating to Autopilot: \"#{prompt}\"")

    case Autopilot.Agent.run(prompt) do
      :ok -> :ok
      {:error, reason} -> {:error, "Autopilot failed: #{inspect(reason)}"}
    end
  end

  defp execute_step(%{"action" => "extract"} = step, _vars) do
    selector = step["selector"]
    var_name = step["variable"] || "result"

    js = """
    (function() {
      var el = document.querySelector('#{escape_js(selector)}');
      if (!el) return JSON.stringify({error: 'not_found'});
      return JSON.stringify({value: (el.innerText || el.textContent || '').trim()});
    })()
    """

    case Autopilot.Browser.eval(js) do
      {:ok, result} ->
        case Jason.decode(result) do
          {:ok, %{"value" => value}} ->
            Logger.info("[Runner] Extracted #{var_name} = #{inspect(value)}")
            IO.puts("  📤 #{var_name}: #{value}")
            :ok

          {:ok, %{"error" => _}} ->
            {:error, "Extract: element not found: #{selector}"}

          _ ->
            {:error, "Extract: could not parse result"}
        end

      error ->
        {:error, error}
    end
  end

  defp execute_step(%{"action" => action}, _vars) do
    {:error, "Unknown action: #{action}"}
  end

  # ── Value resolution ───────────────────────────────────────────

  defp resolve_step_value(%{"variable" => var_name}, vars) when is_binary(var_name) do
    Map.get(vars, var_name, "")
  end

  defp resolve_step_value(%{"value" => value}, _vars), do: value
  defp resolve_step_value(_step, _vars), do: ""

  # ── Browser helpers ────────────────────────────────────────────

  defp get_url do
    Autopilot.Browser.eval("window.location.href")
  end

  defp get_page_text do
    Autopilot.Browser.eval("document.body.innerText.slice(0, 5000)")
  end

  defp element_visible?(selector) do
    js = """
    (function() {
      var el = document.querySelector('#{escape_js(selector)}');
      if (!el) return false;
      var rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    })()
    """
    case Autopilot.Browser.eval(js) do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp wait_for_element(selector, timeout) do
    start = System.monotonic_time(:millisecond)
    do_wait_element(selector, timeout, start)
  end

  defp do_wait_element(selector, timeout, start) do
    if System.monotonic_time(:millisecond) - start > timeout do
      {:error, "Timeout waiting for #{selector}"}
    else
      if element_visible?(selector) do
        :ok
      else
        Process.sleep(500)
        do_wait_element(selector, timeout, start)
      end
    end
  end

  defp wait_for_url_contains(contains, timeout) do
    start = System.monotonic_time(:millisecond)
    do_wait_url(contains, timeout, start)
  end

  defp do_wait_url(contains, timeout, start) do
    if System.monotonic_time(:millisecond) - start > timeout do
      {:error, "Timeout waiting for URL containing \"#{contains}\""}
    else
      {:ok, url} = get_url()
      if String.contains?(url, contains) do
        :ok
      else
        Process.sleep(500)
        do_wait_url(contains, timeout, start)
      end
    end
  end

  defp escape_js(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
end
