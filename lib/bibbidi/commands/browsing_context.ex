defmodule Bibbidi.Commands.BrowsingContext do
  @moduledoc """
  Command builders for the `browsingContext` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Navigates a browsing context to the given URL.

  ## Options

  - `:wait` - When to consider navigation complete. One of `"none"`, `"interactive"`, `"complete"`.
    Defaults to `"none"`.
  """
  @spec navigate(GenServer.server(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def navigate(conn, context, url, opts \\ []) do
    params = %{context: context, url: url}
    params = put_opt(params, :wait, opts)
    Connection.send_command(conn, "browsingContext.navigate", params)
  end

  @doc """
  Gets the browsing context tree.

  ## Options

  - `:max_depth` - Maximum depth of the tree to return.
  - `:root` - Root browsing context ID. If omitted, returns all top-level contexts.
  """
  @spec get_tree(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_tree(conn, opts \\ []) do
    params = %{}
    params = put_opt(params, :max_depth, opts, :maxDepth)
    params = put_opt(params, :root, opts)
    Connection.send_command(conn, "browsingContext.getTree", params)
  end

  @doc """
  Creates a new browsing context.

  ## Options

  - `:reference_context` - An existing context to use as reference.
  - `:background` - Whether to create the context in the background.
  - `:user_context` - The user context to create the browsing context in.
  """
  @spec create(GenServer.server(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create(conn, type \\ "tab", opts \\ []) do
    params = %{type: type}
    params = put_opt(params, :reference_context, opts, :referenceContext)
    params = put_opt(params, :background, opts)
    params = put_opt(params, :user_context, opts, :userContext)
    Connection.send_command(conn, "browsingContext.create", params)
  end

  @doc """
  Closes a browsing context.

  ## Options

  - `:prompt_unload` - Whether to prompt the user before unloading. Defaults to `false`.
  """
  @spec close(GenServer.server(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def close(conn, context, opts \\ []) do
    params = %{context: context}
    params = put_opt(params, :prompt_unload, opts, :promptUnload)
    Connection.send_command(conn, "browsingContext.close", params)
  end

  @doc """
  Captures a screenshot of a browsing context.

  ## Options

  - `:origin` - Origin of the screenshot. One of `"viewport"`, `"document"`.
  - `:format` - Image format map, e.g. `%{type: "image/png"}`.
  - `:clip` - Clipping region.
  """
  @spec capture_screenshot(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def capture_screenshot(conn, context, opts \\ []) do
    params = %{context: context}
    params = put_opt(params, :origin, opts)
    params = put_opt(params, :format, opts)
    params = put_opt(params, :clip, opts)
    Connection.send_command(conn, "browsingContext.captureScreenshot", params)
  end

  @doc """
  Prints a browsing context to PDF.

  ## Options

  - `:background` - Whether to print background graphics.
  - `:margin` - Page margins map.
  - `:orientation` - `"portrait"` or `"landscape"`.
  - `:page` - Page size map.
  - `:page_ranges` - List of page ranges.
  - `:scale` - Scale factor.
  - `:shrink_to_fit` - Whether to shrink to fit.
  """
  @spec print(GenServer.server(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def print(conn, context, opts \\ []) do
    params = %{context: context}
    params = put_opt(params, :background, opts)
    params = put_opt(params, :margin, opts)
    params = put_opt(params, :orientation, opts)
    params = put_opt(params, :page, opts)
    params = put_opt(params, :page_ranges, opts, :pageRanges)
    params = put_opt(params, :scale, opts)
    params = put_opt(params, :shrink_to_fit, opts, :shrinkToFit)
    Connection.send_command(conn, "browsingContext.print", params)
  end

  @doc """
  Reloads a browsing context.

  ## Options

  - `:ignore_cache` - Whether to ignore the cache.
  - `:wait` - When to consider reload complete.
  """
  @spec reload(GenServer.server(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def reload(conn, context, opts \\ []) do
    params = %{context: context}
    params = put_opt(params, :ignore_cache, opts, :ignoreCache)
    params = put_opt(params, :wait, opts)
    Connection.send_command(conn, "browsingContext.reload", params)
  end

  @doc """
  Sets the viewport size for a browsing context.
  Pass `nil` for viewport to reset to default.
  """
  @spec set_viewport(GenServer.server(), String.t(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_viewport(conn, context, viewport, opts \\ []) do
    params = %{context: context}

    params =
      if viewport, do: Map.put(params, :viewport, viewport), else: Map.put(params, :viewport, nil)

    params = put_opt(params, :device_pixel_ratio, opts, :devicePixelRatio)
    Connection.send_command(conn, "browsingContext.setViewport", params)
  end

  @doc """
  Handles a user prompt (alert, confirm, prompt dialog).
  """
  @spec handle_user_prompt(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def handle_user_prompt(conn, context, opts \\ []) do
    params = %{context: context}
    params = put_opt(params, :accept, opts)
    params = put_opt(params, :user_text, opts, :userText)
    Connection.send_command(conn, "browsingContext.handleUserPrompt", params)
  end

  @doc """
  Activates (brings to focus) a browsing context.
  """
  @spec activate(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def activate(conn, context) do
    Connection.send_command(conn, "browsingContext.activate", %{context: context})
  end

  @doc """
  Traverses the browsing history by a given delta.
  """
  @spec traverse_history(GenServer.server(), String.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  def traverse_history(conn, context, delta) do
    Connection.send_command(conn, "browsingContext.traverseHistory", %{
      context: context,
      delta: delta
    })
  end

  @doc """
  Locates nodes in a browsing context.
  """
  @spec locate_nodes(GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def locate_nodes(conn, context, locator, opts \\ []) do
    params = %{context: context, locator: locator}
    params = put_opt(params, :max_node_count, opts, :maxNodeCount)
    params = put_opt(params, :start_nodes, opts, :startNodes)
    Connection.send_command(conn, "browsingContext.locateNodes", params)
  end

  ## Private helpers

  defp put_opt(params, key, opts, json_key \\ nil) do
    json_key = json_key || key

    case Keyword.get(opts, key) do
      nil -> params
      value -> Map.put(params, json_key, value)
    end
  end
end
