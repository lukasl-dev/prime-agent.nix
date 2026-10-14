{
  self,
  jail-nix,
  optionPath ? [ "prime-agent" ],
}:
{
  config,
  options,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  defaultPackage = self.packages.${system}.prime-agent;
  cfg = lib.attrByPath optionPath { } config;
in
{
  options = lib.setAttrByPath optionPath {
    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The Prime Agent package to install.";
    };

    jail = {
      enable = lib.mkEnableOption "bubblewrap isolation for Prime Agent using jail.nix";

      permissions = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.raw);
        default =
          combinators: with combinators; [
            network
            mount-cwd
          ];
        defaultText = lib.literalExpression ''
          combinators: with combinators; [
            network
            mount-cwd
          ]
        '';
        description = ''
          Permissions passed to jail.nix. The default permits model and kernel
          downloads and mounts the invocation's working directory read-write.

          Prime Agent's user configuration and default Python kernel state are
          mounted separately and need not be listed here. Daemon socket state is
          retained between invocations, and files referenced by
          `environment.*.file` are exposed read-only automatically. The jail is
          available only on Linux.
        '';
        example = lib.literalExpression ''
          combinators: with combinators; [
            network
            mount-cwd
            (add-pkg-deps [ pkgs.gnumake pkgs.python3 ])
            (try-readonly (noescape "~/.gitconfig"))
          ]
        '';
      };
    };

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a models.json file installed into Prime Agent's configuration
        directory and kept in sync before each invocation. The default
        directory is {file}`~/.prime/agent` and can be changed with
        `environment.PRIME_AGENT_CODING_AGENT_DIR`.
      '';
      example = lib.literalExpression "./models.json";
    };

    rules = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.either lib.types.lines (lib.types.addCheck lib.types.path builtins.isPath)
      );
      default = null;
      description = "Instructions appended to headless launches. Prime Agent 0.10 does not forward CLI prompt overrides to its interactive TUI.";
      example = lib.literalExpression "./AGENTS.md";
    };

    extensions = lib.mkOption {
      type = lib.types.unspecified;
      visible = false;
      apply =
        _:
        throw "Prime Agent 0.10 removed JavaScript/TypeScript user extensions. Remove the extensions option.";
    };

    skills = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Skill paths installed into settings and passed to headless launches.";
    };

    themes = lib.mkOption {
      type = lib.types.unspecified;
      visible = false;
      apply =
        _:
        throw "Prime Agent 0.10 does not load custom theme paths. Use settings.theme with prime, dark or light.";
    };

    promptTemplates = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Prompt template paths installed into settings and passed to headless launches.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Raw CLI arguments prepended when launching an agent.";
      example = lib.literalExpression ''[ "--provider" "openai" "--model" "gpt-5" ]'';
    };

    environment = lib.mkOption {
      type =
        let
          nixPath = lib.types.addCheck lib.types.path builtins.isPath;
          taggedValue = lib.types.attrTag {
            file = lib.mkOption {
              type = lib.types.either lib.types.str nixPath;
              description = "File whose contents are exported at runtime.";
            };
            value = lib.mkOption {
              type = lib.types.str;
              description = "Literal value to export.";
            };
          };
          environmentValue =
            (lib.types.coercedTo (lib.types.either lib.types.str nixPath) (
              legacyValue:
              throw ''
                Direct ${if builtins.isString legacyValue then "string" else "Nix path"}
                environment values are ambiguous. Use `{ value = ...; }` for a
                literal or `{ file = ...; }` for a runtime secret file.
              ''
            ) taggedValue)
            // {
              description = "attribute set containing exactly one of `file` or `value`";
            };
          attrs = lib.types.submodule {
            freeformType = lib.types.attrsOf environmentValue;
            options.PRIME_AGENT_CODING_AGENT_DIR = lib.mkOption {
              type = lib.types.nullOr environmentValue;
              default = null;
              description = "Prime Agent's user configuration directory.";
              example = lib.literalExpression ''{ value = "''${config.home.homeDirectory}/.prime/agent"; }'';
            };
          };
          checkedAttrs = lib.types.addCheck attrs (
            values: lib.all lib.isValidPosixName (builtins.attrNames values)
          );
        in
        lib.types.nullOr (
          (lib.types.either lib.types.path checkedAttrs)
          // {
            inherit (attrs) getSubOptions;
            description = "shell environment file or attribute set with POSIX environment variable names";
          }
        );
      default = null;
      description = ''
        Environment exported before Prime Agent starts. This may be a shell
        environment file, or an attribute set of explicit `{ value = ...; }`
        and `{ file = ...; }` entries. File entries are read at runtime so they
        work with secret managers such as sops-nix.
      '';
      example = lib.literalExpression ''
        {
          PRIME_AGENT_CODING_AGENT_DIR.value = "/home/user/.prime/agent";
          OPENAI_API_KEY.file = config.sops.secrets.openai-api-key.path;
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Values merged into the global settings.json before each invocation.";
    };

    finalRules = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      internal = true;
      readOnly = true;
    };
    finalArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      readOnly = true;
    };
    finalPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };

  config = lib.setAttrByPath optionPath (
    let
      inherit (cfg)
        package
        jail
        models
        rules
        skills
        promptTemplates
        extraArgs
        environment
        settings
        ;

      pathFlags =
        flag: paths:
        lib.concatMap (path: [
          flag
          "${path}"
        ]) paths;

      rulesPath =
        if rules == null then
          null
        else if builtins.isPath rules then
          rules
        else
          pkgs.writeText "prime-agent-AGENTS.md" rules;

      resourceArgs =
        (lib.optionals (rulesPath != null) [
          "--append-system-prompt"
          (if builtins.isPath rules then builtins.readFile rules else rules)
        ])
        ++ pathFlags "--skill" skills
        ++ pathFlags "--prompt-template" promptTemplates;

      envPrelude = lib.optionalString (environment != null) (
        if lib.isAttrs environment && !lib.isDerivation environment then
          lib.concatLines (
            lib.mapAttrsToList (
              name: value:
              if value ? file then
                ''
                  ${name}="$(cat ${lib.escapeShellArg "${value.file}"})"
                  export ${name}
                ''
              else
                "export ${lib.escapeShellArg name}=${lib.escapeShellArg value.value}"
            ) (lib.filterAttrs (_: value: value != null) environment)
          )
        else
          ''
            set -a
            . ${lib.escapeShellArg "${environment}"}
            set +a
          ''
      );

      resourceSettings =
        settings
        // lib.optionalAttrs (skills != [ ]) {
          skills = (settings.skills or [ ]) ++ map (path: "${path}") skills;
        }
        // lib.optionalAttrs (promptTemplates != [ ]) {
          prompts = (settings.prompts or [ ]) ++ map (path: "${path}") promptTemplates;
        };

      configDirPrelude = lib.optionalString (models != null || resourceSettings != { }) ''
        PRIME_AGENT_CODING_AGENT_DIR="''${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}"
        export PRIME_AGENT_CODING_AGENT_DIR
      '';

      modelsPrelude = lib.optionalString (models != null) ''
        models_file="$PRIME_AGENT_CODING_AGENT_DIR/models.json"
        if [ -L "$models_file" ]; then rm "$models_file"; fi

        mkdir -p "$PRIME_AGENT_CODING_AGENT_DIR"
        tmp="$(mktemp "$PRIME_AGENT_CODING_AGENT_DIR/models.json.XXXXXX")"
        install -m 0600 ${lib.escapeShellArg "${models}"} "$tmp"
        if [ ! -f "$models_file" ] || ! ${pkgs.diffutils}/bin/cmp -s "$tmp" "$models_file"; then
          mv "$tmp" "$models_file"
        else
          rm "$tmp"
        fi
      '';

      settingsPath =
        if resourceSettings == { } then
          null
        else
          pkgs.writeText "prime-agent-settings.json" (builtins.toJSON resourceSettings);

      settingsPrelude = lib.optionalString (settingsPath != null) ''
        settings_file="$PRIME_AGENT_CODING_AGENT_DIR/settings.json"
        if [ -L "$settings_file" ]; then rm "$settings_file"; fi

        mkdir -p "$PRIME_AGENT_CODING_AGENT_DIR"
        tmp="$(mktemp "$PRIME_AGENT_CODING_AGENT_DIR/settings.json.XXXXXX")"
        if [ -f "$settings_file" ]; then
          ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$settings_file" ${lib.escapeShellArg settingsPath} > "$tmp"
        else
          printf '%s\n' '{}' | ${lib.getExe pkgs.jq} -s '.[0] * .[1]' - ${lib.escapeShellArg settingsPath} > "$tmp"
        fi
        chmod 0600 "$tmp"
        if [ ! -f "$settings_file" ] || ! ${pkgs.diffutils}/bin/cmp -s "$tmp" "$settings_file"; then
          mv "$tmp" "$settings_file"
        else
          rm "$tmp"
        fi
      '';

      argsStr = lib.concatMapStringsSep " " lib.escapeShellArg resourceArgs;
      extraArgsStr = lib.concatMapStringsSep " " lib.escapeShellArg extraArgs;

      wrapped =
        if
          resourceArgs == [ ]
          && environment == null
          && models == null
          && settingsPath == null
          && extraArgs == [ ]
        then
          package
        else
          pkgs.writeShellScriptBin "prime-agent" ''
            set -euo pipefail

            ${envPrelude}
            ${configDirPrelude}
            ${modelsPrelude}
            ${settingsPrelude}

            # Resource and model-selection flags belong to agent launches, not
            # to Prime Agent's public management subcommands.
            case "''${1-}" in
              agents)
                exec ${lib.escapeShellArg (lib.getExe package)} agents ${argsStr} ${extraArgsStr} "''${@:2}"
                ;;
              attach)
                if [ "$#" -ge 2 ]; then
                  exec ${lib.escapeShellArg (lib.getExe package)} attach "$2" ${argsStr} ${extraArgsStr} "''${@:3}"
                fi
                exec ${lib.escapeShellArg (lib.getExe package)} "$@"
                ;;
              help|list|sessions|stop|rename|send|schedule|status|doctor|telemetry|incident|shutdown|package|mcp|update|model|session|prompt|factory|config|app|daemon|install|manage|remove|uninstall)
                exec ${lib.escapeShellArg (lib.getExe package)} "$@"
                ;;
              *)
                exec ${lib.escapeShellArg (lib.getExe package)} ${argsStr} ${extraArgsStr} "$@"
                ;;
            esac
          '';

      jailAgentDirRuntime =
        if
          environment != null
          && lib.isAttrs environment
          && !lib.isDerivation environment
          && environment.PRIME_AGENT_CODING_AGENT_DIR != null
        then
          if environment.PRIME_AGENT_CODING_AGENT_DIR ? file then
            ''agent_dir="$(cat ${lib.escapeShellArg "${environment.PRIME_AGENT_CODING_AGENT_DIR.file}"})"''
          else
            "agent_dir=${lib.escapeShellArg environment.PRIME_AGENT_CODING_AGENT_DIR.value}"
        else if environment != null && (!lib.isAttrs environment || lib.isDerivation environment) then
          ''
            agent_dir="$(${pkgs.runtimeShell} -c '
              exec 3>&1
              set -a
              . ${lib.escapeShellArg "${environment}"} >&2
              set +a
              printf %s "''${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}" >&3
            ')"
          ''
        else
          ''agent_dir="''${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}"'';

      environmentFiles =
        if environment == null then
          [ ]
        else if lib.isAttrs environment && !lib.isDerivation environment then
          lib.mapAttrsToList (_: value: value.file) (
            lib.filterAttrs (_: value: value != null && value ? file) environment
          )
        else
          [ environment ];

      jailEnvironmentFilesRuntime = lib.concatMapStringsSep "\n" (file: ''
        environment_file=${lib.escapeShellArg "${file}"}
        if [ ! -e "$environment_file" ]; then
          echo "prime-agent: environment file does not exist: $environment_file" >&2
          exit 1
        fi
        environment_source="$(realpath "$environment_file")"
        RUNTIME_ARGS+=(--ro-bind "$environment_source" "$environment_file")
      '') environmentFiles;
    in
    {
      finalRules = rulesPath;
      finalArgs = resourceArgs ++ extraArgs;
      finalPackage =
        if (lib.getAttrFromPath (optionPath ++ [ "extensions" ]) options).isDefined then
          throw "Prime Agent 0.10 removed JavaScript/TypeScript user extensions. Remove the extensions option."
        else if (lib.getAttrFromPath (optionPath ++ [ "themes" ]) options).isDefined then
          throw "Prime Agent 0.10 does not load custom theme paths. Use settings.theme with prime, dark or light."
        else if jail.enable && !pkgs.stdenv.hostPlatform.isLinux then
          throw "prime-agent.jail is supported only on Linux"
        else if jail.enable then
          let
            jailBuilder = jail-nix.lib.init pkgs;
            inherit (jailBuilder) combinators;
            statePermission = combinators.compose [
              (combinators.add-runtime ''
                ${jailAgentDirRuntime}
                case "$agent_dir" in /*) ;; *) agent_dir="$PWD/$agent_dir" ;; esac

                # The kernel venv defaults to ~/.prime/agent independently of
                # PRIME_AGENT_CODING_AGENT_DIR, so retain both locations when
                # a custom configuration directory is selected.
                for state_dir in "$HOME/.prime/agent" "$agent_dir"; do
                  mkdir -p -- "$state_dir"
                  state_source="$(realpath "$state_dir")"
                  RUNTIME_ARGS+=(--bind "$state_source" "$state_dir")
                done

                # Prime Agent discovers its daemon socket below TMPDIR. jail.nix
                # otherwise gives every invocation a fresh /tmp, which would
                # make the detached daemon unreachable by later invocations.
                daemon_tmp_dir="$agent_dir/tmp"
                mkdir -p -- "$daemon_tmp_dir"
                RUNTIME_ARGS+=(--setenv TMPDIR "$daemon_tmp_dir")

                # Environment values tagged with `file` are read by the inner
                # wrapper. Expose only those individual files rather than their
                # containing secret directories.
                ${jailEnvironmentFilesRuntime}
              '')
              combinators.no-die-with-parent
              (combinators.try-fwd-env "PRIME_AGENT_CODING_AGENT_DIR")
              (combinators.try-fwd-env "PRIME_AGENT_DAEMON_SOCKET")
              (combinators.try-fwd-env "PRIME_AGENT_KERNEL_PYTHON")
              (combinators.try-fwd-env "PRIME_AGENT_KERNEL_VENV")
            ];
          in
          jailBuilder "prime-agent" wrapped (jail.permissions combinators ++ [ statePermission ])
        else
          wrapped;
    }
  );
}
