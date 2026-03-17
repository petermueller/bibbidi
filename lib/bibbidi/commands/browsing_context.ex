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
    Connection.execute(conn, %__MODULE__.Navigate{
      context: context,
      url: url,
      wait: opts[:wait]
    })
  end

  @doc """
  Gets the browsing context tree.

  ## Options

  - `:max_depth` - Maximum depth of the tree to return.
  - `:root` - Root browsing context ID. If omitted, returns all top-level contexts.
  """
  @spec get_tree(GenServer.server(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_tree(conn, opts \\ []) do
    Connection.execute(conn, %__MODULE__.GetTree{
      max_depth: opts[:max_depth],
      root: opts[:root]
    })
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
    Connection.execute(conn, %__MODULE__.Create{
      type: type,
      reference_context: opts[:reference_context],
      background: opts[:background],
      user_context: opts[:user_context]
    })
  end

  @doc """
  Closes a browsing context.

  ## Options

  - `:prompt_unload` - Whether to prompt the user before unloading. Defaults to `false`.
  """
  @spec close(GenServer.server(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def close(conn, context, opts \\ []) do
    Connection.execute(conn, %__MODULE__.Close{
      context: context,
      prompt_unload: opts[:prompt_unload]
    })
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
    Connection.execute(conn, %__MODULE__.CaptureScreenshot{
      context: context,
      origin: opts[:origin],
      format: opts[:format],
      clip: opts[:clip]
    })
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
    Connection.execute(conn, %__MODULE__.Print{
      context: context,
      background: opts[:background],
      margin: opts[:margin],
      orientation: opts[:orientation],
      page: opts[:page],
      page_ranges: opts[:page_ranges],
      scale: opts[:scale],
      shrink_to_fit: opts[:shrink_to_fit]
    })
  end

  @doc """
  Reloads a browsing context.

  ## Options

  - `:ignore_cache` - Whether to ignore the cache.
  - `:wait` - When to consider reload complete.
  """
  @spec reload(GenServer.server(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def reload(conn, context, opts \\ []) do
    Connection.execute(conn, %__MODULE__.Reload{
      context: context,
      ignore_cache: opts[:ignore_cache],
      wait: opts[:wait]
    })
  end

  @doc """
  Sets the viewport size for a browsing context.
  Pass `nil` for viewport to reset to default.
  """
  @spec set_viewport(GenServer.server(), String.t(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_viewport(conn, context, viewport, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetViewport{
      context: context,
      viewport: viewport,
      device_pixel_ratio: opts[:device_pixel_ratio]
    })
  end

  @doc """
  Handles a user prompt (alert, confirm, prompt dialog).
  """
  @spec handle_user_prompt(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def handle_user_prompt(conn, context, opts \\ []) do
    Connection.execute(conn, %__MODULE__.HandleUserPrompt{
      context: context,
      accept: opts[:accept],
      user_text: opts[:user_text]
    })
  end

  @doc """
  Activates (brings to focus) a browsing context.
  """
  @spec activate(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def activate(conn, context) do
    Connection.execute(conn, %__MODULE__.Activate{context: context})
  end

  @doc """
  Traverses the browsing history by a given delta.
  """
  @spec traverse_history(GenServer.server(), String.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  def traverse_history(conn, context, delta) do
    Connection.execute(conn, %__MODULE__.TraverseHistory{context: context, delta: delta})
  end

  @doc """
  Locates nodes in a browsing context.
  """
  @spec locate_nodes(GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def locate_nodes(conn, context, locator, opts \\ []) do
    Connection.execute(conn, %__MODULE__.LocateNodes{
      context: context,
      locator: locator,
      max_node_count: opts[:max_node_count],
      start_nodes: opts[:start_nodes]
    })
  end
end
