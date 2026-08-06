{
  self,
  lib,
  jail-nix,
}:
{
  mkAgent =
    {
      pkgs,
      modules ? [ ],
      extraSpecialArgs ? { },
    }:
    let
      evaluated = lib.evalModules {
        specialArgs = {
          inherit self pkgs;
        }
        // extraSpecialArgs;
        modules = [ (import ./modules/options.nix { inherit self jail-nix; }) ] ++ modules;
      };
      inherit (evaluated.config.prime-agent) finalPackage finalRules finalArgs;
    in
    {
      inherit (evaluated) config options;
      prime-agent = finalPackage;
      package = finalPackage;
      rules = finalRules;
      args = finalArgs;
    };
}
