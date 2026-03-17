defmodule OpWorkflow.Op do
  @moduledoc """
  Multi-style pipeline builder for composing BiDi commands.

  This is example code demonstrating one way to orchestrate multiple
  BiDi commands. Copy it into your project and modify as needed.

  ## Usage

      alias OpWorkflow.Op
      alias Bibbidi.Commands.BrowsingContext

      op =
        Op.new()
        |> Op.send(:navigate, %BrowsingContext.Navigate{
          context: ctx, url: "https://example.com", wait: "complete"
        })
        |> Op.send(:tree, %BrowsingContext.GetTree{})

      {:ok, results, operation} = OpWorkflow.Runner.execute(conn, op)
  """

  defstruct steps: []

  @type t :: %__MODULE__{steps: [{atom(), step()}]}

  @type step ::
          {:send, Bibbidi.Encodable.t()}
          | {:send_fn,
             (results() -> {:send, Bibbidi.Encodable.t()} | {:ok, term()} | {:error, term()})}
          | {:run,
             (GenServer.server(), results(), keyword() -> {:ok, term()} | {:error, term()})}
          | {:branch_fn,
             (results() -> {:send, Bibbidi.Encodable.t()} | {:ok, term()} | {:error, term()})}

  @type results :: %{atom() => {:ok, term()} | {:error, term()}}

  @doc "Create a new empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Add a command to send over the wire.

  When `command_or_fn` is an `Encodable` struct, it is sent directly.
  When it is a function, it receives the accumulated results map and
  must return `{:send, command}`, `{:ok, value}`, or `{:error, reason}`.
  """
  @spec send(t(), atom(), Bibbidi.Encodable.t() | (results() -> term())) :: t()
  def send(%__MODULE__{} = op, name, %{__struct__: _} = command) do
    validate_name!(op, name)
    %{op | steps: op.steps ++ [{name, {:send, command}}]}
  end

  def send(%__MODULE__{} = op, name, fun) when is_function(fun, 1) do
    validate_name!(op, name)
    %{op | steps: op.steps ++ [{name, {:send_fn, fun}}]}
  end

  @doc """
  Add an arbitrary step that receives the connection and results.

  The function should return `{:ok, value}` or `{:error, reason}`.
  Use this for operations like polling/waiting that need direct
  connection access.
  """
  @spec run(t(), atom(), (GenServer.server(), results(), keyword() -> term())) :: t()
  def run(%__MODULE__{} = op, name, fun) when is_function(fun, 3) do
    validate_name!(op, name)
    %{op | steps: op.steps ++ [{name, {:run, fun}}]}
  end

  @doc """
  Add a branching step that decides what to do based on previous results.

  The function receives the accumulated results and must return
  `{:send, command}`, `{:ok, value}`, or `{:error, reason}`.
  """
  @spec branch(t(), atom(), (results() -> term())) :: t()
  def branch(%__MODULE__{} = op, name, fun) when is_function(fun, 1) do
    validate_name!(op, name)
    %{op | steps: op.steps ++ [{name, {:branch_fn, fun}}]}
  end

  defp validate_name!(%__MODULE__{steps: steps}, name) do
    if List.keymember?(steps, name, 0) do
      raise ArgumentError, "step name #{inspect(name)} is already used in this pipeline"
    end
  end
end