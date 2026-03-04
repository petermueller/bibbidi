# Add a Command to an Existing Module

When asked to add a new command to an existing BiDi protocol module:

## Steps

1. **Check the CDDL spec** — Search `priv/cddl/remote.cddl` for the command definition (e.g., `browsingContext.NewCommand`). It will have:
   - A group with `method: "module.commandName"` and `params: module.CommandNameParameters`
   - A parameters map type with required/optional fields

2. **Read the existing command module** — Look at `lib/bibbidi/commands/<module>.ex` for the established pattern (positional args, keyword opts, `put_opt` helper).

3. **Add the function** to the command module:
   - Required params as positional arguments
   - Optional params as keyword opts
   - Map snake_case to camelCase for JSON keys
   - Return `Connection.send_command(conn, "module.commandName", params)`

4. **Add unit tests** to `test/bibbidi/commands/<module>_test.exs`:
   - Use `Task.async` + `assert_receive {:mock_transport_send, json}` pattern
   - Verify method name and params
   - Reply with mock response and verify return value

5. **Regenerate types** — Run `mix bibbidi.gen` if the command introduces new types.

## Example

```elixir
# In lib/bibbidi/commands/browsing_context.ex
def new_command(conn, required_arg, opts \\ []) do
  params = %{requiredArg: required_arg}
  params = put_opt(params, :optional_thing, opts, :optionalThing)
  Connection.send_command(conn, "browsingContext.newCommand", params)
end
```

## Checklist

- [ ] Function added with correct method name
- [ ] Required params are positional, optional are keyword
- [ ] camelCase keys in the params map
- [ ] @doc and @spec added
- [ ] Unit test verifying method + params
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` passes
