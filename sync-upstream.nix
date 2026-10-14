{ pkgs }:
pkgs.writeShellApplication {
  name = "prime-agent-update";
  runtimeInputs = with pkgs; [
    coreutils
    gawk
    git
    gnugrep
    gnused
    jq
    nix
  ];
  text = ''
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    rev="$(git ls-remote --tags --refs https://github.com/PrimeIntellect-ai/prime-agent.git 'v*' \
      | awk -F/ '{ print $3 }' \
      | grep -E '^v[0-9]+(\.[0-9]+)*$' \
      | sort -V \
      | tail -n1)"
    test -n "$rev"

    source_json="$(nix store prefetch-file --json --unpack \
      "https://github.com/PrimeIntellect-ai/prime-agent/archive/refs/tags/$rev.tar.gz")"
    hash="$(jq -r .hash <<< "$source_json")"
    src="$(jq -r .storePath <<< "$source_json")"

    for file in Cargo.toml Cargo.lock prime-agent-runtime/uv.lock; do
      if [ ! -f "$src/$file" ]; then
        echo "Prime Agent $rev has no $file; review upstream packaging before updating" >&2
        exit 1
      fi
    done

    cat > "$tmpdir/cargo-deps.nix" <<NIX
    let
      pkgs = import ${pkgs.path} { };
    in
    pkgs.rustPlatform.fetchCargoVendor {
      src = builtins.storePath "$src";
      hash = pkgs.lib.fakeHash;
    }
    NIX

    if nix build --file "$tmpdir/cargo-deps.nix" --no-link > "$tmpdir/cargo-deps.log" 2>&1; then
      echo "Expected the fake Cargo dependency hash to fail" >&2
      exit 1
    fi
    cargo_hash="$(sed -n 's/^[[:space:]]*got:[[:space:]]*//p' "$tmpdir/cargo-deps.log" | tail -n1)"
    if [[ ! "$cargo_hash" =~ ^sha256- ]]; then
      cat "$tmpdir/cargo-deps.log" >&2
      echo "Could not determine the Cargo dependency hash" >&2
      exit 1
    fi

    catalog_rev="$(git ls-remote https://github.com/PrimeIntellect-ai/prime-agent-catalog.git refs/heads/main | awk '{ print $1 }')"
    test -n "$catalog_rev"
    catalog_json="$(nix store prefetch-file --json --unpack \
      "https://github.com/PrimeIntellect-ai/prime-agent-catalog/archive/$catalog_rev.tar.gz")"
    catalog_hash="$(jq -r .hash <<< "$catalog_json")"

    jq -n --arg rev "$rev" --arg hash "$hash" --arg cargoHash "$cargo_hash" \
      --arg catalogRev "$catalog_rev" --arg catalogHash "$catalog_hash" \
      '{rev: $rev, hash: $hash, cargoHash: $cargoHash, catalog: {rev: $catalogRev, hash: $catalogHash}}' \
      > "$tmpdir/VERSION.json"

    cp "$src/Cargo.lock" Cargo.lock
    cp "$src/prime-agent-runtime/uv.lock" uv.lock
    cp "$tmpdir/VERSION.json" VERSION.json
    echo "Updated Prime Agent source and dependency locks to $rev"
  '';
}
