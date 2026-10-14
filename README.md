# prime-agent.nix

Unofficial Nix packaging and configurable NixOS/Home Manager wrappers for
[Prime Agent](https://github.com/PrimeIntellect-ai/prime-agent).

```sh
nix run github:lukasl-dev/prime-agent.nix
nix build .#prime-agent
nix flake check
```

The native Rust package includes its Python runtime sources, a Nix Python
interpreter, Git, SSH, ripgrep, fd and uv. First kernel use provisions Python
dependencies through uv and needs network access.

## Configuration

```nix
{
  inputs.prime-agent.url = "github:lukasl-dev/prime-agent.nix";
}
```

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.prime-agent.nixosModules.default ];

  programs.prime-agent = {
    enable = true;
    settings.defaultProvider = "openai";
    settings.defaultModel = "gpt-5";
    environment.OPENAI_API_KEY.file = config.sops.secrets.openai-api-key.path;
    # rules = ./AGENTS.md;
    # skills = [ ./skills ];
    # settings.theme = "dark";
    # promptTemplates = [ ./prompts ];
    # models = ./models.json;
    # jail.enable = true;
  };
}
```

For Home Manager use `inputs.prime-agent.homeModules.default` with the same
options. Configuration defaults to `~/.prime/agent`; override it with
`environment.PRIME_AGENT_CODING_AGENT_DIR.value`.

Pass a common skills directory, preserving each child skill's directory name:
`skills = [ ./skills ];`.

The flake also exports `overlays.default` (`pkgs.prime-agent`) and
`lib.mkAgent { inherit pkgs; modules = [ ... ]; }` (`.package`).
[Option reference](https://lukasl-dev.github.io/prime-agent.nix/), or build it
locally with `nix build .#docs-html`.

## Updating

```sh
nix run .#update
nix run .#scan
nix flake check
```

`Cargo.lock` tracks the native application; `uv.lock` mirrors upstream's Python
development lock (kernel bootstrap resolves dependencies separately). The
updater follows stable upstream tags and pins a real model/MCP catalogue snapshot.

Prime Agent 0.10 replaced its Node implementation with Rust. The Bun package
and JavaScript/TypeScript extension option have been removed; existing extension
configurations must be removed too. Custom theme paths are not implemented in
the Rust TUI; use `settings.theme` (`prime`, `dark`, `light`). The upstream TUI
also ignores CLI prompt overrides, so `rules` currently applies to headless
launches only. Skills and prompt templates are written to settings for both
modes. Package updates are managed by Nix, not the application's self-updater.
