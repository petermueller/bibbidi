defmodule Autopilot.Tools.Wait do
  @moduledoc "Wait tools: wait_for_selector, wait_for_url, wait_for_loading."

  alias LangChain.Function
  alias LangChain.FunctionParam

  def wait_for_selector do
    Function.new!(%{
      name: "wait_for_selector",
      description: "Wait until a CSS selector is visible. Use after clicks that trigger loading.",
      parameters: [
        FunctionParam.new!(%{name: "selector", type: :string, required: true,
          description: "CSS selector to wait for, e.g. '#login-form'"}),
        FunctionParam.new!(%{name: "timeout_ms", type: :integer, required: false,
          description: "Max wait in ms (default 10000)"})
      ],
      function: fn args, _context ->
        selector = args["selector"]
        timeout  = args["timeout_ms"] || 10_000

        js = """
        new Promise((resolve, reject) => {
          const start = Date.now();
          const check = () => {
            const el = document.querySelector('#{selector}');
            const visible = el && el.offsetParent !== null && el.offsetWidth > 0;
            if (visible) return resolve(true);
            if (Date.now() - start > #{timeout}) return reject('timeout');
            setTimeout(check, 150);
          };
          check();
        })
        """

        try do
          case Autopilot.Browser.eval(js, timeout + 5_000) do
            {:ok, _}         -> {:ok, "Element '#{selector}' is visible."}
            {:error, reason} -> {:ok, "wait_for_selector '#{selector}' timed out: #{inspect(reason)}"}
          end
        catch
          :exit, {:timeout, _} ->
            {:ok, "wait_for_selector '#{selector}' timed out. Proceeding anyway."}
        end
      end
    })
  end

  def wait_for_url do
    Function.new!(%{
      name: "wait_for_url",
      description: "Wait until the URL contains a string. Use after form submissions or redirects.",
      parameters: [
        FunctionParam.new!(%{name: "contains", type: :string, required: true,
          description: "String the URL must contain, e.g. 'dashboard'"}),
        FunctionParam.new!(%{name: "timeout_ms", type: :integer, required: false,
          description: "Max wait in ms (default 15000)"})
      ],
      function: fn args, _context ->
        contains = args["contains"]
        timeout  = args["timeout_ms"] || 15_000

        js = """
        new Promise((resolve, reject) => {
          const start = Date.now();
          const check = () => {
            if (window.location.href.includes('#{contains}')) return resolve(window.location.href);
            if (Date.now() - start > #{timeout}) return reject('timeout. current: ' + window.location.href);
            setTimeout(check, 200);
          };
          check();
        })
        """

        try do
          case Autopilot.Browser.eval(js, timeout + 5_000) do
            {:ok, result}    -> {:ok, "URL matched '#{contains}': #{inspect(result)}"}
            {:error, reason} -> {:ok, "URL did not match '#{contains}' within timeout: #{inspect(reason)}"}
          end
        catch
          :exit, {:timeout, _} ->
            {:ok, "wait_for_url '#{contains}' timed out. Proceeding anyway."}
        end
      end
    })
  end

  def wait_for_loading do
    Function.new!(%{
      name: "wait_for_loading",
      description: "Wait for page to finish loading. Use after clicks that trigger API calls or page loads.",
      parameters: [
        FunctionParam.new!(%{name: "timeout_ms", type: :integer, required: false,
          description: "Max wait in ms (default 15000)"})
      ],
      function: fn args, _context ->
        timeout = args["timeout_ms"] || 15_000

        js = """
        new Promise((resolve) => {
          const start = Date.now();
          const isDone = () => {
            if (document.readyState !== 'complete') return false;
            const selectors = ['.loading', '.spinner', '.loader', '[aria-busy="true"]'];
            for (const sel of selectors) {
              const el = document.querySelector(sel);
              if (el && el.offsetParent !== null) return false;
            }
            return true;
          };
          const check = () => {
            if (isDone()) return resolve('done');
            if (Date.now() - start > #{timeout}) return resolve('timeout');
            setTimeout(check, 200);
          };
          setTimeout(check, 300);
        })
        """

        try do
          case Autopilot.Browser.eval(js, timeout + 5_000) do
            {:ok, _}         -> {:ok, "Page loaded."}
            {:error, reason} -> {:ok, "Proceeding: #{inspect(reason)}"}
          end
        catch
          :exit, {:timeout, _} ->
            {:ok, "Page load wait timed out. Proceeding anyway."}
        end
      end
    })
  end
end
