#!/usr/bin/env bash
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-1200}"

formula_path="${FORMULA_PATH:-./Formula/zotero-pdf2zh.rb}"
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
}
trap cleanup EXIT

brew install --formula "$formula_path"
brew test zotero-pdf2zh
rm -f "$marker"

zotero-pdf2zh --port "$port" --check_update false >"$log_file" 2>&1 &
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
