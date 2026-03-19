#!/usr/bin/env bash
set -euo pipefail

formula_path="${FORMULA_PATH:-Formula/zotero-pdf2zh.rb}"
upstream_repo="${UPSTREAM_REPO:-guaguastandup/zotero-pdf2zh}"
output_file="${GITHUB_OUTPUT:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

emit_output() {
  local key="$1"
  local value="$2"
  if [ -n "$output_file" ]; then
    printf '%s=%s\n' "$key" "$value" >>"$output_file"
  fi
}

current_version="$(ruby -e 'text = File.read(ARGV[0]); match = text.match(%r{releases/download/(v[^/]+)/}); puts(match ? match[1] : "")' "$formula_path")"
current_sha="$(ruby -e 'text = File.read(ARGV[0]); match = text.match(/^  sha256 \"([0-9a-f]{64})\"/); puts(match ? match[1] : "")' "$formula_path")"
zero_sha="0000000000000000000000000000000000000000000000000000000000000000"

if ! release_json="$(gh api "repos/${upstream_repo}/releases/latest")"; then
  echo "No stable upstream release found." >&2
  exit 1
fi

latest_version="$(jq -r '.tag_name // empty' <<<"$release_json")"

if [ -z "$latest_version" ]; then
  echo "No stable upstream release found." >&2
  exit 1
fi

asset_name="$(jq -r '([.assets[]? | select(.name == "server.zip")] + [.assets[]? | select(.name | endswith(".zip"))])[0].name // empty' <<<"$release_json")"
asset_url="$(jq -r --arg asset_name "$asset_name" '.assets[]? | select(.name == $asset_name) | .browser_download_url // empty' <<<"$release_json")"
asset_digest="$(jq -r --arg asset_name "$asset_name" '.assets[]? | select(.name == $asset_name) | .digest // empty' <<<"$release_json")"

if [ -z "$asset_name" ] || [ -z "$asset_url" ]; then
  echo "Release ${latest_version} does not expose a usable zip asset." >&2
  exit 1
fi

if [[ "$asset_digest" == sha256:* ]]; then
  asset_sha="${asset_digest#sha256:}"
else
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  gh release download "$latest_version" -R "$upstream_repo" -p "$asset_name" -D "$tmpdir" >/dev/null
  asset_sha="$(shasum -a 256 "$tmpdir/$asset_name" | awk '{print $1}')"
fi

emit_output current_version "$current_version"
emit_output latest_version "$latest_version"
emit_output asset_name "$asset_name"
emit_output asset_url "$asset_url"
emit_output sha256 "$asset_sha"
emit_output branch_name "bump-zotero-pdf2zh-${latest_version}"

if [ "$current_version" = "$latest_version" ] && [ -n "$current_sha" ] && [ "$current_sha" != "$zero_sha" ] && [ "$current_sha" = "$asset_sha" ]; then
  emit_output update_needed false
  exit 0
fi

ruby - "$formula_path" "$asset_url" "$asset_sha" <<'RUBY'
formula_path, asset_url, asset_sha = ARGV
text = File.read(formula_path)
updated = text.sub(/^  url ".*"$/, "  url \"#{asset_url}\"")
updated = updated.sub(/^  sha256 ".*"$/, "  sha256 \"#{asset_sha}\"")
updated = updated.sub(/^  revision \d+\n/, "")
if updated == text
  warn "Formula update produced no changes."
  exit 1
end
File.write(formula_path, updated)
RUBY

emit_output update_needed true
