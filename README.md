# prime-agent.nix

<p align="center">
  <a href="https://lukasl-dev.github.io/prime-agent.nix/">
    <img src="https://img.shields.io/badge/docs-options-5277C3?style=for-the-badge&logo=nixos&logoColor=white" alt="Options">
  </a>
</p>

A Nix flake for [Prime Agent](https://github.com/PrimeIntellect-ai/prime-agent), a self-improving RLM agent for coding and long-running autonomous work.

It provides:

- packages for `nix run` and `nix build`
- a default npm-built package and an optional Bun-built variant
- NixOS and Home Manager modules
- an overlay exposing `pkgs.prime-agent` and `pkgs.prime-agent-bun`
- `lib.mkPrimeAgent` for constructing a configured wrapper
- automatic stable-release and dependency-lock updates

> [!IMPORTANT]
> This is an unofficial Nix flake and is not maintained by Prime Intellect.

## Quick start

```bash
nix run github:lukasl-dev/prime-agent.nix --accept-flake-config
```

Or build either implementation locally:

```bash
nix build .#prime-agent --accept-flake-config
nix build .#prime-agent-bun --accept-flake-config
```

The package includes Node.js, Git, SSH, ripgrep, fd, and uv in its runtime path. Prime Agent uses uv for the one-time provisioning of its persistent IPython kernel under `~/.prime/agent/kernel-venv`.

## Usage

```nix
{
  inputs.prime-agent.url = "github:lukasl-dev/prime-agent.nix";
}
```

### NixOS

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.prime-agent.nixosModules.default ];

  programs.prime-agent = {
    enable = true;
    # rules = ''Be concise.'';
    # skills = [ ./skills/my-skill ];
    # extensions = [ ./extensions/my-extension.ts ];
    # themes = [ ./themes/custom.json ];
    # promptTemplates = [ ./prompts ];
    # models = ./models.json;
    # settings.model = "gpt-5";
    # jail.enable = true;
    # extraArgs = [ "--provider" "openai" "--model" "gpt-5" ];
    # environment.OPENAI_API_KEY.file = config.sops.secrets.openai-api-key.path;
  };
}
```

### Home Manager

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.prime-agent.homeModules.default ];

  programs.prime-agent = {
    enable = true;
    settings.model = "gpt-5";
    environment.PRIME_AGENT_CODING_AGENT_DIR.value =
      "${config.home.homeDirectory}/.prime/agent";
  };
}
```

### Overlay

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.prime-agent.overlays.default ];
  environment.systemPackages = [ pkgs.prime-agent ];
}
```

### Custom package

```nix
{ inputs, pkgs, ... }:
let
  agent = inputs.prime-agent.lib.mkPrimeAgent {
    inherit pkgs;
    modules = [{
      prime-agent = {
        rules = ''Be concise.'';
        skills = [ ./skills/my-skill ];
      };
    }];
  };
in
agent.package
```

### Jail

On Linux, Prime Agent can run in a [jail.nix](https://sr.ht/~alexdavid/jail.nix/) bubblewrap sandbox:

```nix
programs.prime-agent.jail.enable = true;
```

The default jail permits network access and mounts the invocation's working directory read-write. It also retains `~/.prime/agent` and the configured `PRIME_AGENT_CODING_AGENT_DIR`, allowing daemon state and the IPython kernel to survive invocations. Other home files and host tools remain unavailable unless explicitly exposed.

```nix
programs.prime-agent.jail.permissions = combinators: with combinators; [
  network
  mount-cwd
  (add-pkg-deps [ pkgs.gnumake pkgs.python3 ])
  (try-readonly (noescape "~/.gitconfig"))
];
```

### Selecting the Bun package

```nix
programs.prime-agent.package =
  inputs.prime-agent.packages.${pkgs.system}.prime-agent-bun;
```

## Options

Generate the complete option reference in Markdown or HTML:

```bash
nix build .#docs-md
nix build .#docs-html
```

The output is available at `result/index.md` or `result/index.html`.
