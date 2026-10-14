{ pkgs }:
pkgs.writeShellApplication {
  name = "prime-agent-scan";
  runtimeInputs = with pkgs; [
    gitleaks
    osv-scanner
    zizmor
  ];
  text = ''
    zizmor .github/workflows
    osv-scanner scan source --lockfile Cargo.lock --lockfile uv.lock
    gitleaks dir --redact --config .gitleaks.toml .
  '';
}
