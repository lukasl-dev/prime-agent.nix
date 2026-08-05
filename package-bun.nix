{
  lib,
  stdenv,
  bun2nix,
  bun,
  nodejs_22,
  python3,
  makeWrapper,
  pkg-config,
  gitMinimal,
  openssh,
  ripgrep,
  fd,
  uv,
  pixman,
  cairo,
  pango,
  libpng,
  libjpeg,
  giflib,
  librsvg,
  src,
  version,
}:
let
  nodejs = nodejs_22;
  runtimeBins = lib.makeBinPath [
    nodejs
    gitMinimal
    openssh
    ripgrep
    fd
    uv
  ];

  bunInstallFlags =
    if stdenv.hostPlatform.isDarwin then
      [
        "--linker=hoisted"
        "--backend=copyfile"
        "--frozen-lockfile"
        "--offline"
      ]
    else
      [
        "--linker=hoisted"
        "--frozen-lockfile"
        "--offline"
      ];
in
stdenv.mkDerivation {
  pname = "prime-agent-bun";
  inherit src version bunInstallFlags;

  nativeBuildInputs = [
    bun2nix.hook
    bun
    nodejs
    makeWrapper
    gitMinimal
    pkg-config
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

  bunDeps = bun2nix.fetchBunDeps {
    bunNix =
      {
        copyPathToStore,
        fetchFromGitHub,
        fetchgit,
        fetchurl,
        ...
      }@args:
      import ./bun.nix args;
  };

  # Native packages in this dependency graph ship suitable prebuilt artifacts.
  # Running arbitrary package lifecycle scripts would both be unnecessary and
  # violate the build's network isolation.
  dontRunLifecycleScripts = true;

  # canvas does not ship a native artifact in its npm tarball. Lifecycle
  # scripts remain disabled globally; rebuild only this known addon against
  # the pinned Node headers and the Nix-provided graphics libraries.
  postBunNodeModulesInstallPhase = ''
    pushd node_modules/canvas
    PATH=${nodejs}/bin:$PATH PYTHON=${python3}/bin/python3 \
      ${nodejs}/bin/node \
      ${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js \
      rebuild --nodedir=${nodejs}

    releaseDir="$(mktemp -d)"
    cp build/Release/*.node "$releaseDir/"
    rm -rf build
    mkdir -p build/Release
    cp "$releaseDir"/*.node build/Release/
    popd
  '';

  preBuild = ''
        substituteInPlace packages/ai/package.json \
          --replace-fail 'npm run generate-models && ' '''

        find packages -name package.json -exec sed -i \
          -e 's/--watch --preserveWatchOutput//g' \
          {} \;

        # Workspace scripts are written for npm. Bun executes the same script
        # bodies, but recursive npm invocations would escape Bun's workspace
        # installation and are therefore rewritten before building.
        cat > patch-package-json.js <<'BUN'
    const fs = require("fs");
    for (const file of [
      "packages/tui/package.json",
      "packages/ai/package.json",
      "packages/agent/package.json",
      "packages/coding-agent/package.json",
    ]) {
      const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
      for (const [name, script] of Object.entries(pkg.scripts ?? {})) {
        pkg.scripts[name] = script.replaceAll("npm run ", "bun run ");
      }
      fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");
    }
    BUN
        bun patch-package-json.js
        rm patch-package-json.js

        # The dependency install intentionally uses a flattened synthetic root
        # package to avoid Bun's registry-manifest lookups for workspaces. Link
        # the four build workspaces back into Node resolution after install.
        mkdir -p node_modules/@earendil-works
        ln -s ../../packages/tui node_modules/@earendil-works/pi-tui
        ln -s ../../packages/ai node_modules/@earendil-works/pi-ai
        ln -s ../../packages/agent node_modules/@earendil-works/pi-agent-core
        ln -s ../../packages/coding-agent node_modules/@earendil-works/pi-coding-agent
  '';

  buildPhase = ''
    runHook preBuild
    for pkg in tui ai agent coding-agent; do
      (cd "packages/$pkg" && bun run build)
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    packageDir="$out/lib/node_modules/@earendil-works/pi-coding-agent"
    mkdir -p "$out/bin" "$packageDir" "$out/lib/node_modules/@earendil-works"

    for pkg in tui ai agent; do
      mkdir -p "$out/lib/node_modules/@earendil-works/pi-$pkg"
      cp -r "packages/$pkg/dist" "$out/lib/node_modules/@earendil-works/pi-$pkg/"
      cp "packages/$pkg/package.json" "$out/lib/node_modules/@earendil-works/pi-$pkg/"
    done

    cp -r packages/coding-agent/dist "$packageDir/"
    for path in package.json README.md CHANGELOG.md docs examples skills postinstall.cjs; do
      [ ! -e "packages/coding-agent/$path" ] || cp -r "packages/coding-agent/$path" "$packageDir/"
    done

    rm node_modules/@earendil-works/pi-{tui,ai,agent-core,coding-agent}
    cp -rL node_modules/. "$out/lib/node_modules/"

    # Prime Agent's zeromq addon calls libuv APIs that Bun 1.3 does not yet
    # implement (uv_async_init). Dependencies and sources are built with Bun,
    # but the resulting ESM bundle must run on the supported Node 22 runtime.
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
    description = "Self-improving RLM agent (dependencies and sources built with Bun)";
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
