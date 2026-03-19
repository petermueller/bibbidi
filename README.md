# Bibbidi Monorepo

Elixir implementation of the [W3C WebDriver BiDi Protocol](https://w3c.github.io/webdriver-bidi/).

## Structure

```
packages/
└── bibbidi/       — core hex package (WebDriver BiDi client)
```

## Setup

This monorepo uses [workspace](https://hexdocs.pm/workspace) for multi-package management.

```sh
mix deps.get
```

## Common Commands

Run a mix command across all packages:

```sh
mix workspace.run -t test
mix workspace.run -t format
mix workspace.run -t deps.get
```

Run tests for a specific package:

```sh
cd packages/bibbidi && mix test
```

List workspace projects:

```sh
mix workspace.list
```

Check workspace status:

```sh
mix workspace.status
```

See individual package READMEs for package-specific instructions.
