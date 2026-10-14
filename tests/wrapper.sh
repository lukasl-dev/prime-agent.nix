set -euo pipefail
: "${configured:?}" "${missingSecret:?}" "${rules:?}" "${skills:?}" "${prompts:?}" "${models:?}" "${compare:?}"

export HOME="$PWD/home"
export PRIME_AGENT_CODING_AGENT_DIR="$HOME/custom agent"
mkdir -p "$PRIME_AGENT_CODING_AGENT_DIR"
printf '%s\n' '{"fixture":{"owner":"retained"}}' > "$PRIME_AGENT_CODING_AGENT_DIR/settings.json"

"$configured" 'a message with spaces' --model user-choice > launch.json
jq -e --rawfile rules "$rules" --arg skills "$skills" --arg prompts "$prompts" '
  .args == ["--append-system-prompt", $rules, "--skill", $skills,
    "--prompt-template", $prompts, "--provider", "openai", "--model", "gpt-5",
    "a message with spaces", "--model", "user-choice"]
  and .secret == "synthetic-test-token"
  and .literal == "literal with spaces and '\''quotes'\''"
' launch.json

"$compare" "$models" "$PRIME_AGENT_CODING_AGENT_DIR/models.json"
jq -e --arg skills "$skills" --arg prompts "$prompts" '
  .fixture == {owner: "retained", managed: true}
  and .defaultProvider == "openai" and .defaultModel == "gpt-5"
  and .skills == [$skills] and .prompts == [$prompts]
' "$PRIME_AGENT_CODING_AGENT_DIR/settings.json"
test "$(stat -c %a "$PRIME_AGENT_CODING_AGENT_DIR/models.json")" = 600
test "$(stat -c %a "$PRIME_AGENT_CODING_AGENT_DIR/settings.json")" = 600
models_inode="$(stat -c %i "$PRIME_AGENT_CODING_AGENT_DIR/models.json")"
settings_inode="$(stat -c %i "$PRIME_AGENT_CODING_AGENT_DIR/settings.json")"

for command in help list sessions stop rename send schedule status doctor telemetry incident \
  shutdown package mcp update model session prompt factory config app daemon install manage remove uninstall; do
  "$configured" "$command" '--help' > command.json
  jq -e --arg command "$command" '.args == [$command, "--help"]' command.json
done
test "$(stat -c %i "$PRIME_AGENT_CODING_AGENT_DIR/models.json")" = "$models_inode"
test "$(stat -c %i "$PRIME_AGENT_CODING_AGENT_DIR/settings.json")" = "$settings_inode"

"$configured" agents --help > agents.json
jq -e '.args[0] == "agents" and .args[1] == "--append-system-prompt" and .args[-1] == "--help"' agents.json
"$configured" attach 'session selector' --help > attach.json
jq -e '.args[0:3] == ["attach", "session selector", "--append-system-prompt"] and .args[-1] == "--help"' attach.json
"$configured" attach > attach-missing.json
jq -e '.args == ["attach"]' attach-missing.json

printf 'owner models\n' > owner-models
rm "$PRIME_AGENT_CODING_AGENT_DIR/models.json"
ln -s "$PWD/owner-models" "$PRIME_AGENT_CODING_AGENT_DIR/models.json"
"$configured" status > /dev/null
test ! -L "$PRIME_AGENT_CODING_AGENT_DIR/models.json"
"$compare" "$models" "$PRIME_AGENT_CODING_AGENT_DIR/models.json"
test "$(<owner-models)" = 'owner models'

export WRAPPER_MARKER="$PWD/should-not-run"
if "$missingSecret" status > /dev/null 2> missing-secret.log; then
  echo 'A missing secret did not stop the wrapper' >&2
  exit 1
fi
test ! -e "$WRAPPER_MARKER"
