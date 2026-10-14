{
  pkgs,
  self,
  package,
  src,
}:
let
  inherit (pkgs) lib;
  fixture = {
    rules = ./fixtures/AGENTS.md;
    skills = [ ./fixtures/skills ];
    promptTemplates = [ ./fixtures/prompts ];
    models = ./fixtures/models.json;
    settings = {
      defaultProvider = "openai";
      defaultModel = "gpt-5";
      telemetry.enabled = false;
      fixture.managed = true;
    };
    environment = {
      WRAPPER_SECRET.file = ./fixtures/token;
      WRAPPER_LITERAL.value = "literal with spaces and 'quotes'";
    };
    extraArgs = [
      "--provider"
      "openai"
      "--model"
      "gpt-5"
    ];
  };

  mock = pkgs.writeShellScriptBin "prime-agent" ''
    if [ -n "''${WRAPPER_MARKER-}" ]; then touch "$WRAPPER_MARKER"; fi
    ${lib.getExe pkgs.jq} -n \
      --argjson args "$(${lib.getExe pkgs.jq} -cn --args '$ARGS.positional' -- "$@")" \
      --arg secret "''${WRAPPER_SECRET-}" \
      --arg literal "''${WRAPPER_LITERAL-}" \
      '{args: $args, secret: $secret, literal: $literal}'
  '';

  configured =
    selectedPackage:
    (self.lib.mkAgent {
      inherit pkgs;
      modules = [
        {
          prime-agent = fixture // {
            package = selectedPackage;
          };
        }
      ];
    }).package;

  missingSecret =
    (self.lib.mkAgent {
      inherit pkgs;
      modules = [
        {
          prime-agent = {
            package = mock;
            environment.WRAPPER_SECRET.file = "/missing-prime-agent-nix-fixture";
          };
        }
      ];
    }).package;

  rejectedOption =
    name: value:
    !(builtins.tryEval
      (self.lib.mkAgent {
        inherit pkgs;
        modules = [
          {
            prime-agent = {
              package = mock;
            }
            // {
              ${name} = value;
            };
          }
        ];
      }).package
    ).success;
in
assert rejectedOption "extensions" [ ];
assert rejectedOption "themes" [ ];
{
  package = package;

  locks = pkgs.runCommand "prime-agent-source-locks" { } ''
    cmp ${../Cargo.lock} ${src}/Cargo.lock
    cmp ${../uv.lock} ${src}/prime-agent-runtime/uv.lock
    touch $out
  '';

  wrapper =
    pkgs.runCommand "prime-agent-wrapper-check"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.coreutils
          pkgs.shellcheck
        ];
      }
      ''
        export configured=${lib.getExe (configured mock)}
        export missingSecret=${lib.getExe missingSecret}
        export rules=${./fixtures/AGENTS.md}
        export skills=${./fixtures/skills}
        export prompts=${./fixtures/prompts}
        export models=${./fixtures/models.json}
        export compare=${pkgs.diffutils}/bin/cmp
        shellcheck -s bash ${./wrapper.sh}
        PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.bash
            pkgs.jq
          ]
        } bash ${./wrapper.sh}
        touch $out
      '';

  installed =
    pkgs.runCommand "prime-agent-installed-check"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.coreutils
          pkgs.python3
          pkgs.shellcheck
        ];
      }
      ''
        export agent=${lib.getExe package}
        export configured=${lib.getExe (configured package)}
        export payload=${package}/share/prime-agent
        export version=${package.version}
        export rules=${./fixtures/AGENTS.md}
        export source=${src}
        shellcheck -s bash ${./installed.sh}
        bash ${./installed.sh}
        touch $out
      '';
}
