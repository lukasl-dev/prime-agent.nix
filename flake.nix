{
  description = "Nix packaging and modules for Prime Agent";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      jail-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        { pkgs, ... }:
        let
          current = builtins.fromJSON (builtins.readFile ./VERSION.json);
          inherit (current) rev hash cargoHash;
          version = nixpkgs.lib.removePrefix "v" rev;

          src = pkgs.fetchFromGitHub {
            owner = "PrimeIntellect-ai";
            repo = "prime-agent";
            inherit rev hash;
          };

          catalogSrc = pkgs.fetchFromGitHub {
            owner = "PrimeIntellect-ai";
            repo = "prime-agent-catalog";
            inherit (current.catalog) rev hash;
          };

          syncUpstream = import ./sync-upstream.nix { inherit pkgs; };
          scan = import ./scan.nix { inherit pkgs; };
        in
        {
          packages = rec {
            default = prime-agent;

            prime-agent = pkgs.callPackage ./packages/package.nix {
              inherit
                src
                catalogSrc
                version
                cargoHash
                ;
            };

            docs-md =
              let
                agent = self.lib.mkAgent { inherit pkgs; };
                docs = pkgs.nixosOptionsDoc {
                  options = builtins.removeAttrs agent.options [ "_module" ];
                };
              in
              pkgs.runCommand "prime-agent-options.md" { } ''
                mkdir -p $out
                cp ${docs.optionsCommonMark} $out/index.md
              '';

            docs-html =
              pkgs.runCommand "prime-agent-options.html"
                {
                  nativeBuildInputs = [ pkgs.pandoc ];
                }
                ''
                  mkdir -p $out
                  pandoc \
                    --standalone \
                    --metadata title="prime-agent.nix options" \
                    ${docs-md}/index.md \
                    --output $out/index.html
                '';
          };

          checks = import ./tests {
            inherit pkgs self src;
            package = self.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent;
          };

          formatter = pkgs.nixfmt-tree;

          apps = {
            update = {
              type = "app";
              program = "${syncUpstream}/bin/prime-agent-update";
            };
            sync-upstream = {
              type = "app";
              program = "${syncUpstream}/bin/prime-agent-update";
            };
            scan = {
              type = "app";
              program = "${scan}/bin/prime-agent-scan";
            };
          };
        };

      flake = {
        lib =
          let
            prime-agent = import ./lib.nix {
              inherit self jail-nix;
              inherit (nixpkgs) lib;
            };
          in
          {
            inherit (prime-agent) mkAgent;
          };

        nixosModules = rec {
          default = prime-agent;
          prime-agent = import ./modules/nixos.nix { inherit self jail-nix; };
        };

        homeModules = rec {
          default = prime-agent;
          prime-agent = import ./modules/home-manager.nix { inherit self jail-nix; };
        };

        homeManagerModules = self.homeModules;

        overlays.default =
          _final: prev:
          let
            inherit (prev.stdenv.hostPlatform) system;
          in
          {
            prime-agent = self.packages.${system}.prime-agent;
          };
      };
    };
}
