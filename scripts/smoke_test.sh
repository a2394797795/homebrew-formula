#!/usr/bin/env bash
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-1200}"

formula_path="${FORMULA_PATH:-./Formula/zotero-pdf2zh.rb}"
tap_name="${TAP_NAME:-local/zotero-pdf2zh-smoke}"
formula_name="${FORMULA_NAME:-zotero-pdf2zh-smoke}"
formula_class_name="${FORMULA_CLASS_NAME:-$(ruby -e 'puts ARGV.fetch(0).split(/[^a-zA-Z0-9]+/).reject(&:empty?).map(&:capitalize).join' "$formula_name")}"
command_name="${COMMAND_NAME:-zotero-pdf2zh}"
port="${ZOTERO_PDF2ZH_TEST_PORT:-47701}"
health_url="http://127.0.0.1:${port}/health"
prefix="$(brew --prefix)"
log_file="${RUNNER_TEMP:-/tmp}/zotero-pdf2zh-smoke.log"
marker="${prefix}/var/zotero-pdf2zh/needs-deps-update"

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  brew uninstall --force "$formula_name" >/dev/null 2>&1 || true
  if brew tap | grep -qx "$tap_name"; then
    brew untap "$tap_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

tap_repo="$(brew --repository "$tap_name" 2>/dev/null || true)"
if [ -n "$tap_repo" ] && [ -e "$tap_repo" ]; then
  brew untap "$tap_name"
fi
git config --global user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
brew tap-new "$tap_name"
tap_repo="$(brew --repository "$tap_name")"
temp_formula="$tap_repo/Formula/${formula_name}.rb"
cp "$formula_path" "$temp_formula"
ruby - "$temp_formula" "$formula_class_name" <<'RUBY'
formula_path = ARGV.fetch(0)
formula_class_name = ARGV.fetch(1)
text = File.read(formula_path)
unless text.sub!(/^class\s+\S+\s+<\s+Formula$/, "class #{formula_class_name} < Formula")
  warn "Unable to rewrite formula class name for smoke test"
  exit 1
end
File.write(formula_path, text)
RUBY

echo "Smoke-test formula:"
sed -n '1,12p' "$temp_formula"
brew info --json=v2 "$tap_name/$formula_name" | ruby -rjson -e '
  info = JSON.parse(STDIN.read).fetch("formulae").fetch(0)
  puts "Resolved version: #{info.dig("versions", "stable")}"
  puts "Resolved URL: #{info.dig("urls", "stable", "url")}"
'

brew uninstall --force "$formula_name" >/dev/null 2>&1 || true
brew install "$tap_name/$formula_name"
brew test "$tap_name/$formula_name"
rm -f "$marker"

"$command_name" --port "$port" --check_update false >"$log_file" 2>&1 &
server_pid=$!

for _ in $(seq 1 180); do
  if curl -fsS "$health_url" >/dev/null 2>&1; then
    curl -fsS "$health_url"
    exit 0
  fi
  sleep 2
done

echo "Smoke test failed; service never became healthy." >&2
if [ -f "$log_file" ]; then
  tail -n 200 "$log_file" >&2 || true
fi
exit 1
