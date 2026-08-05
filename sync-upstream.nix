{
  pkgs,
  bun2nix,
}:
pkgs.writeShellApplication {
  name = "prime-agent-update";
  runtimeInputs = with pkgs; [
    bun
    coreutils
    gawk
    git
    gnugrep
    gnused
    jq
    nix
    nodejs
    npm-lockfile-fix
    prefetch-npm-deps
    bun2nix
  ];
  text = ''
    set -euo pipefail

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

    cp -R "$src"/. "$tmpdir"
    chmod -R u+w "$tmpdir"
    npm-lockfile-fix "$tmpdir/package-lock.json"

    pushd "$tmpdir" >/dev/null
    # npm exits 1 when the only remaining result is a known advisory against
    # the workspace package itself. Preserve any remediations it made, but do
    # not mistake that false positive for an updater failure.
    set +e
    npm audit fix --package-lock-only --ignore-scripts
    audit_status=$?
    set -e
    if [ "$audit_status" -gt 1 ]; then exit "$audit_status"; fi

    # Bun re-resolves semver ranges in every workspace after noticing the
    # private root's redundant coding-agent dependency. Pin external direct
    # dependencies from package-lock.json and use explicit workspace specs so
    # the Nix build needs package tarballs, but no mutable registry manifests.
    node ${./scripts/pin-bun-dependencies.mjs} "$tmpdir" --flatten

    mv package-lock.json package-lock.npm.json
    bun install --ignore-scripts
    mv package-lock.npm.json package-lock.json
    bun2nix -o bun.nix
    popd >/dev/null

    # Fetcher v2 stores npm's registry metadata as well as package tarballs.
    # Prime Agent's lockfile needs that metadata for scoped dependencies whose
    # upstream lock entries npm cannot consume in cache-only mode.
    cat > "$tmpdir/npm-deps.nix" <<'NIX'
    let
      pkgs = import ${pkgs.path} { };
    in
    pkgs.fetchNpmDeps {
      src = ./.;
      hash = pkgs.lib.fakeHash;
      fetcherVersion = 2;
    }
    NIX

    set +e
    npm_deps_log="$(nix-build "$tmpdir/npm-deps.nix" --no-out-link 2>&1)"
    npm_deps_status=$?
    set -e
    if [ "$npm_deps_status" -eq 0 ]; then
      echo "Expected the fake npm dependency hash to fail" >&2
      exit 1
    fi
    npm_deps_hash="$(sed -n 's/^[[:space:]]*got:[[:space:]]*//p' <<< "$npm_deps_log" | tail -n1)"
    if [[ ! "$npm_deps_hash" =~ ^sha256- ]]; then
      printf '%s\n' "$npm_deps_log" >&2
      echo "Could not determine the npm dependency hash" >&2
      exit 1
    fi

    jq \
      --arg rev "$rev" \
      --arg hash "$hash" \
      --arg npmDepsHash "$npm_deps_hash" \
      '.rev = $rev | .hash = $hash | .npmDepsHash = $npmDepsHash' \
      VERSION.json > "$tmpdir/VERSION.json"

    cp "$tmpdir/package-lock.json" package-lock.json
    cp "$tmpdir/bun.lock" bun.lock
    cp "$tmpdir/bun.nix" bun.nix
    cp "$tmpdir/VERSION.json" VERSION.json
    echo "Updated Prime Agent lockfiles and VERSION.json to $rev"
  '';
}
