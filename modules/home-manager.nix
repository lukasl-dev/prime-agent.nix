{ self, jail-nix }:
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.prime-agent;
in
{
  imports = [
    (import ./options.nix {
      inherit self jail-nix;
      optionPath = [
        "programs"
        "prime-agent"
      ];
    })
  ];

  options.programs.prime-agent.enable = lib.mkEnableOption "Prime Agent";

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.finalPackage ];
  };
}
