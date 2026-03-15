defmodule Bibbidi.Test.NavigateAndGetTree do
  @moduledoc false
  defstruct [:context, :url]

  defimpl Bibbidi.Expandable do
    def expand(%{context: ctx, url: url}) do
      [
        %Bibbidi.Commands.BrowsingContext.Navigate{context: ctx, url: url, wait: "complete"},
        %Bibbidi.Commands.BrowsingContext.GetTree{}
      ]
    end
  end
end

defmodule Bibbidi.Test.LocateAndActivate do
  @moduledoc false
  defstruct [:context, :selector]

  defimpl Bibbidi.Expandable do
    def expand(%{context: ctx, selector: sel}) do
      locate = %Bibbidi.Commands.BrowsingContext.LocateNodes{
        context: ctx,
        locator: %{type: "css", value: sel}
      }

      {locate,
       fn
         {:ok, %{"nodes" => [_ | _]}} ->
           {:cont, %Bibbidi.Commands.BrowsingContext.Activate{context: ctx}}

         {:ok, %{"nodes" => []}} ->
           {:halt, {:error, :not_found}}
       end}
    end
  end
end
