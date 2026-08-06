{
  description = "Nix packaging and modules for Prime Agent";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    bun2nix = {
      url = "github:nix-community/bun2nix?ref=2.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      bun2nix,
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
        { system, pkgs, ... }:
        let
          current = builtins.fromJSON (builtins.readFile ./VERSION.json);
          inherit (current) rev hash npmDepsHash;
          version = nixpkgs.lib.removePrefix "v" rev;

          src = pkgs.fetchFromGitHub {
            owner = "PrimeIntellect-ai";
            repo = "prime-agent";
            inherit rev hash;
          };

          syncUpstream = import ./sync-upstream.nix {
            inherit pkgs;
            bun2nix = bun2nix.packages.${system}.bun2nix;
          };
          scan = import ./scan.nix { inherit pkgs; };
        in
        {
          packages = rec {
            default = prime-agent;

            prime-agent = pkgs.callPackage ./packages/package.nix {
              inherit src version npmDepsHash;
            };

            prime-agent-bun =
              let
                bunPkgs = import nixpkgs {
                  inherit system;
                  overlays = [ bun2nix.overlays.default ];
                };

                # Upstream publishes only package-lock.json. bun2nix installs
                # dependencies before a derivation's normal build hooks, so provide
                # Bun with a source tree that already contains our generated lock.
                bunSrc =
                  bunPkgs.runCommand "prime-agent-${version}-source-with-bun-lock"
                    { nativeBuildInputs = [ bunPkgs.nodejs ]; }
                    ''
                      mkdir -p $out
                      cp -R ${src}/. $out/
                      chmod -R u+w $out
                      cp ${./package-lock.json} $out/package-lock.json
                      node ${./scripts/pin-bun-dependencies.mjs} $out --flatten
                      cp ${./bun.lock} $out/bun.lock
                      rm $out/package-lock.json
                    '';
              in
              bunPkgs.callPackage ./packages/package-bun.nix {
                src = bunSrc;
                inherit version;
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

          formatter = pkgs.nixfmt;

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
            prime-agent-bun = self.packages.${system}.prime-agent-bun;
          };
      };
    };
}
