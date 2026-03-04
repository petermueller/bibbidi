# Implement a BiDi Protocol Module

When asked to implement a new WebDriver BiDi protocol module (e.g., `network`, `storage`, `input`, `browser`, `log`, `emulation`, `webExtension`):

## Steps

1. **Check the CDDL spec** — Read `priv/cddl/remote.cddl` for commands the client sends, and `priv/cddl/local.cddl` for responses/events the client receives. Search for the module name (e.g., `NetworkCommand`, `network.`).

2. **Create the command module** at `lib/bibbidi/commands/<module_name>.ex`:
   - Module name: `Bibbidi.Commands.<ModuleName>` (e.g., `Bibbidi.Commands.Network`)
   - Each command is a function: `def command_name(conn, required_args..., opts \\ [])`
   - Map snake_case option keys to camelCase JSON keys
   - Call `Bibbidi.Connection.send_command(conn, "module.commandName", params)`
   - Return `{:ok, map()} | {:error, term()}`

3. **Create unit tests** at `test/bibbidi/commands/<module_name>_test.exs`:
   - Use `Bibbidi.MockTransport` (see existing tests for pattern)
   - Test that each command sends the correct method and params
   - Test optional parameters are included when provided

4. **Create integration tests** at `test/integration/<module_name>_test.exs`:
   - Tag with `@moduletag :integration`
   - Use `Bibbidi.IntegrationCase` (handles browser launch + cleanup)
   - Test against a real browser

## Example Pattern

```elixir
defmodule Bibbidi.Commands.Network do
  alias Bibbidi.Connection

  def add_intercept(conn, phases, opts \\ []) do
    params = %{phases: phases}
    params = put_opt(params, :url_patterns, opts, :urlPatterns)
    Connection.send_command(conn, "network.addIntercept", params)
  end

  defp put_opt(params, key, opts, json_key \\ nil) do
    json_key = json_key || key
    case Keyword.get(opts, key) do
      nil -> params
      value -> Map.put(params, json_key, value)
    end
  end
end
```

## Checklist

- [ ] Command module created with all commands from CDDL spec
- [ ] All required params are positional arguments
- [ ] All optional params use keyword opts
- [ ] Unit tests verify method name and param encoding
- [ ] Integration tests cover key commands
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` passes
