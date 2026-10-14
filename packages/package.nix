{
  lib,
  stdenv,
  rustPlatform,
  makeWrapper,
  gitMinimal,
  openssh,
  ripgrep,
  fd,
  uv,
  python3,
  python311,
  src,
  catalogSrc,
  version,
  cargoHash,
}:
rustPlatform.buildRustPackage {
  pname = "prime-agent";
  inherit src version cargoHash;

  nativeBuildInputs = [
    makeWrapper
    python3
  ];

  # uv's downloaded CPython uses a non-Nix dynamic loader. Build the mutable
  # kernel environment around the Nix interpreter instead.
  patches = [ ./kernel-python.patch ];
  postPatch = ''
    substituteInPlace crates/pa-core/src/kernel/bootstrap/venv.rs \
      --replace-fail 'const PYTHON_VERSION: &str = "3.11";' \
        'const PYTHON_VERSION: &str = "${python311}/bin/python3.11";'

    # Keep native supervisors and workers separate from a still-running JS daemon.
    substituteInPlace crates/pa-daemon/src/platform/paths.rs \
      --replace-fail '<tmpdir>/prime-agent-<uid>/' '<tmpdir>/prime-agent-rust-<uid>/' \
      --replace-fail '"prime-agent-{uid}"' '"prime-agent-rust-{uid}"' \
      --replace-fail '"prime-agent-{}", uid.trim()' '"prime-agent-rust-{}", uid.trim()'
  '';

  cargoBuildFlags = [
    "-p"
    "pa-cli"
    "--bin"
    "prime-agent"
  ];
  cargoTestFlags = [
    "-p"
    "pa-cli"
    "--lib"
  ];
  checkFlags = [ "--test-threads=1" ];
  NO_COLOR = "1";

  postInstall = ''
    packageDir="$out/share/prime-agent"
    mkdir -p "$packageDir"
    cp -R prime-agent-runtime skills docs LICENSE README.md "$packageDir/"
    rm -rf "$packageDir/prime-agent-runtime/test" "$packageDir/prime-agent-runtime/uv.lock"
    cat > "$packageDir/package.json" <<'JSON'
    {"version":"${version}","piConfig":{"name":"prime-agent","configDir":".prime/agent"}}
    JSON
    python scripts/release/bundle_catalog.py generate \
      --catalog-dir ${catalogSrc} --out "$packageDir"

    wrapProgram "$out/bin/prime-agent" \
      --set PI_PACKAGE_DIR "$packageDir" \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--suffix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"''} \
      --suffix PATH : "${
        lib.makeBinPath [
          gitMinimal
          openssh
          ripgrep
          fd
          uv
        ]
      }"
  '';

  meta = {
    description = "Self-improving RLM agent for coding and long-running autonomous tasks";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
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
