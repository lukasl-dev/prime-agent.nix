set -euo pipefail
: "${agent:?}" "${configured:?}" "${payload:?}" "${version:?}" "${rules:?}" "${source:?}"

export HOME="$PWD/home"
export TMPDIR="$PWD/tmp"
export XDG_DATA_HOME="$HOME/.local/share"
export PI_OFFLINE=1 DO_NOT_TRACK=1
unset PRIME_AGENT_CODING_AGENT_DIR PRIME_AGENT_DAEMON_SOCKET PRIME_AGENT_FAUX_SCRIPT
mkdir -p "$HOME" "$TMPDIR" work
cd work

test "$("$agent" --version)" = "$version"
"$agent" --help > help.txt
grep -q -- '--skill' help.txt
if "$agent" --extension /unused --help > /dev/null 2> extension.log; then
  echo 'The removed extension flag was accepted' >&2
  exit 1
fi

test -f "$payload/prime-agent-runtime/pyproject.toml"
test -f "$payload/prime-agent-runtime/src/rlm/machines/pr-manager/MACHINE.md"
test -f "$payload/skills/websearch/pyproject.toml"
test -f "$payload/README.md"
python "$source/scripts/release/bundle_catalog.py" verify --out "$payload"
jq -e 'all(.models[]; (.id | startswith("fixture-")) | not)' "$payload/models.bundled.json"

"$configured" prompt --json > prompt.json
jq -e '.prompt | contains("nix-fixture")' prompt.json
export PRIME_AGENT_FAUX_SCRIPT='{"responses":[{"systemPrompt":true}]}'
"$configured" --offline -p 'inspect the prompt' > effective-prompt.txt
while IFS= read -r line; do grep -F -- "$line" effective-prompt.txt; done < "$rules"
grep -F 'nix-fixture' effective-prompt.txt
if grep -F -- "$rules" effective-prompt.txt; then
  echo 'The rule filename leaked into the effective prompt' >&2
  exit 1
fi

export PRIME_AGENT_FAUX_SCRIPT='{"responses":["installed runtime answer"]}'
"$configured" --offline --mode json -p 'test session persistence' > events.jsonl
jq -se 'any(.[]; .type == "session" and .version == 3)
  and any(.[]; .type == "message_end" and .message.role == "assistant"
    and .message.content[0].text == "installed runtime answer")
  and .[-1].type == "agent_end"' events.jsonl
test -n "$(find "$HOME/.prime/agent/sessions" -name '*.jsonl' -print -quit)"
unset PRIME_AGENT_FAUX_SCRIPT

"$agent" --mode daemon > daemon.log 2>&1 &
daemon_pid=$!
trap 'kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true' EXIT
socket="$TMPDIR/prime-agent-rust-$(id -u)/daemon.sock"
for _ in $(seq 1 100); do
  if [ -S "$socket" ]; then break; fi
  if ! kill -0 "$daemon_pid" 2>/dev/null; then cat daemon.log >&2; exit 1; fi
  sleep .05
done
test -S "$socket"

"$agent" list --json > agents.json
jq -e '.sessions == []' agents.json
"$agent" list --json > reconnected.json
cmp agents.json reconnected.json
"$agent" status --json > status.json
jq -e --arg socket "$socket" 'any(.[]; .socketPath == $socket and .status == "current")' status.json
"$agent" shutdown --force > shutdown.txt
for _ in $(seq 1 100); do
  if ! kill -0 "$daemon_pid" 2>/dev/null; then break; fi
  sleep .05
done
if kill -0 "$daemon_pid" 2>/dev/null; then cat shutdown.txt >&2; exit 1; fi
wait "$daemon_pid"
trap - EXIT
