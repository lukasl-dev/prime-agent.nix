{
  lib,
  stdenv,
  buildNpmPackage,
  makeWrapper,
  nodejs_22,
  gitMinimal,
  openssh,
  ripgrep,
  fd,
  uv,
  cmake,
  ninja,
  pkg-config,
  python3,
  pixman,
  cairo,
  pango,
  libpng,
  libjpeg,
  giflib,
  librsvg,
  src,
  version,
  npmDepsHash,
}:
let
  nodejs = nodejs_22;
  buildNpmPackage' = buildNpmPackage.override { inherit nodejs; };
  runtimeBins = lib.makeBinPath [
    nodejs
    gitMinimal
    openssh # Required for Git SSH clones initiated by the agent.
    ripgrep
    fd
    uv # Prime Agent uses uv to provision its persistent IPython kernel.
  ];
in
buildNpmPackage' {
  pname = "prime-agent";
  inherit src version npmDepsHash;
  npmDepsFetcherVersion = 2;

  nativeBuildInputs = [
    makeWrapper
    gitMinimal
    cmake
    ninja
    pkg-config
    python3
  ];

  buildInputs = [
    pixman
    cairo
    pango
    libpng
    libjpeg
    giflib
    librsvg
  ];

  # cmake is available for native npm lifecycle scripts (notably zeromq), but
  # the JavaScript monorepo itself is not a CMake project.
  dontUseCmakeConfigure = true;

  # Keep the audited lockfile in this repository authoritative. Upstream's
  # source archive may contain a different lockfile even when the tag itself
  # has not changed (the updater also normalises and audits this copy).
  prePatch = ''
    cp ${../package-lock.json} package-lock.json
  '';

  preBuild = ''
    # The release already contains generated model metadata. Regenerating it
    # would make the sandboxed build depend on a mutable network service.
    substituteInPlace packages/ai/package.json \
      --replace-fail 'npm run generate-models && ' '''

    # Watch flags are inappropriate for a finite, non-interactive Nix build.
    find packages -name package.json -exec sed -i \
      -e 's/--watch --preserveWatchOutput//g' \
      {} \;
  '';

  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    packageDir="$out/lib/node_modules/@earendil-works/pi-coding-agent"
    mkdir -p "$out/bin" "$packageDir" "$out/lib/node_modules/@earendil-works"

    # Preserve the public libraries for extensions and SDK consumers. The CLI
    # itself uses dist/bundle/cli.js, while package assets are resolved through
    # PI_PACKAGE_DIR at runtime.
    for pkg in tui ai agent; do
      mkdir -p "$out/lib/node_modules/@earendil-works/pi-$pkg"
      cp -r "packages/$pkg/dist" "$out/lib/node_modules/@earendil-works/pi-$pkg/"
      cp "packages/$pkg/package.json" "$out/lib/node_modules/@earendil-works/pi-$pkg/"
    done

    cp -r packages/coding-agent/dist "$packageDir/"
    for path in package.json README.md CHANGELOG.md docs examples skills postinstall.cjs; do
      [ ! -e "packages/coding-agent/$path" ] || cp -r "packages/coding-agent/$path" "$packageDir/"
    done

    cp -rL node_modules/. "$out/lib/node_modules/"

    makeWrapper ${nodejs}/bin/node "$out/bin/prime-agent" \
      --add-flags "$packageDir/dist/bundle/cli.js" \
      --set PI_PACKAGE_DIR "$packageDir" \
      --set PRIME_AGENT_LAUNCHER_PATH "$out/bin/prime-agent" \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --suffix PATH : "${runtimeBins}" \
      --run 'export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/prime-agent/npm}"'

    runHook postInstall
  '';

  meta = {
    description = "Self-improving RLM agent for coding and long-running autonomous tasks";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/blob/v${version}/packages/coding-agent/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "prime-agent";
    platforms = lib.platforms.unix;
    maintainers = [
      {
        name = "Lukas";
        email = "me@lukasl.dev";
        github = "lukasl-dev";
      }
    ];
  };
}
