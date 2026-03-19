#!/usr/bin/env bash
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-1200}"

formula_path="${FORMULA_PATH:-./Formula/zotero-pdf2zh.rb}"
tap_name="${TAP_NAME:-local/zotero-pdf2zh-smoke}"
formula_name="${FORMULA_NAME:-zotero-pdf2zh}"
port="${ZOTERO_PDF2ZH_TEST_PORT:-47701}"
health_url="http://127.0.0.1:${port}/health"
prefix="$(brew --prefix)"
log_file="${RUNNER_TEMP:-/tmp}/zotero-pdf2zh-smoke.log"
marker="${prefix}/var/zotero-pdf2zh/needs-deps-update"
repo_root="$(cd "$(dirname "$formula_path")/.." && pwd)"

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  if brew tap | grep -qx "$tap_name"; then
    brew untap "$tap_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

tap_repo="$(brew --repository "$tap_name" 2>/dev/null || true)"
if [ -n "$tap_repo" ] && [ -e "$tap_repo" ]; then
  brew untap "$tap_name"
fi
brew tap-new "$tap_name"
tap_repo="$(brew --repository "$tap_name")"
cp "$formula_path" "$tap_repo/Formula/${formula_name}.rb"

brew reinstall "$tap_name/$formula_name"
brew test "$tap_name/$formula_name"
rm -f "$marker"

"$formula_name" --port "$port" --check_update false >"$log_file" 2>&1 &
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
