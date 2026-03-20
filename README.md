# Bibbidi Monorepo

Elixir implementation of the [W3C WebDriver BiDi Protocol](https://w3c.github.io/webdriver-bidi/).

## Structure

```
packages/
├── bibbidi/                     — core hex package (WebDriver BiDi client)
├── bibbidi_runic/               — Runic workflow integration
└── bibbidi_playwright_trace/    — Playwright trace file generation
```

## Setup

This monorepo uses [workspace](https://hexdocs.pm/workspace) for multi-package management.

```sh
mix deps.get
```

## Development

Satellite packages (`bibbidi_runic`, `bibbidi_playwright_trace`) can depend on bibbidi via a local path or a Hex version. Set the `BBD_DEV` environment variable to use the local path:

```sh
# Use local bibbidi source for all satellite packages
BBD_DEV=1 mix deps.get

# Use the published Hex version (default)
mix deps.get
```

## Common Commands

Aliases are defined in the root `mix.exs` for common workspace operations:

```sh
mix test.all          # Run tests across all packages
mix format.all        # Format all packages
mix deps.get.all      # Fetch deps for all packages
mix compile.all       # Compile all packages
```

Run a command for a specific package:

```sh
mix workspace.run -t test -p bibbidi
```

Or work directly in a package directory:

```sh
cd packages/bibbidi && mix test
```

### Other Workspace Commands

```sh
mix workspace.list    # List workspace projects
mix workspace.status  # Check workspace status
```

## Environment Variables

All project env vars use the `BBD_` prefix:

| Variable | Description |
| --- | --- |
| `BBD_DEV` | When set, satellite packages depend on bibbidi via `path: "../bibbidi"` instead of Hex |
| `BBD_BROWSER_URL` | Skip browser launch and connect to an existing instance |
| `BBD_DEBUG=1` | Run headed (visible browser window) |

See individual package READMEs for package-specific instructions.
