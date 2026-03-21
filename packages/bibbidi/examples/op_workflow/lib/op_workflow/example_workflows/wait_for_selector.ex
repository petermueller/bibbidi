defmodule OpWorkflow.ExampleWorkflows.WaitForSelector do
  @moduledoc """
  Example: poll for a CSS selector to appear in the DOM.

  This is a plain function intended for use with `Op.run/3`, since
  it needs direct connection access for polling.
  """

  alias Bibbidi.Commands.BrowsingContext

  @doc """
  Wait for `selector` to appear in `context`. Returns `{:ok, nodes_result}`
  on success or `{:error, {:timeout_waiting_for_selector, selector}}` on timeout.

  ## Options

  - `:timeout` — max wait in milliseconds (default: 10_000)
  - `:interval` — poll interval in milliseconds (default: 250)
  """
  def wait(conn, context, selector, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    interval = Keyword.get(opts, :interval, 250)
    max_attempts = div(timeout, interval)
    do_wait(conn, context, selector, 0, max_attempts, interval)
  end

  defp do_wait(_conn, _context, selector, attempts, max, _interval) when attempts >= max do
    {:error, {:timeout_waiting_for_selector, selector}}
  end

  defp do_wait(conn, context, selector, attempts, max, interval) do
    if attempts > 0, do: Process.sleep(interval)

    case Bibbidi.Connection.execute(conn, %BrowsingContext.LocateNodes{
           context: context,
           locator: %{type: "css", value: selector}
         }) do
      {:ok, %{"nodes" => [_ | _]} = result} -> {:ok, result}
      {:ok, %{"nodes" => []}} -> do_wait(conn, context, selector, attempts + 1, max, interval)
      {:error, reason} -> {:error, reason}
    end
  end
end
