#!/usr/bin/env bash
set -euo pipefail

keepalive_file="${KEEPALIVE_FILE:-.github/workflow-keepalive}"
base_ref="${KEEPALIVE_BASE_REF:-HEAD}"
threshold_days="${KEEPALIVE_AFTER_DAYS:-45}"
now_epoch="${KEEPALIVE_NOW_EPOCH:-$(date +%s)}"
output_file="${GITHUB_OUTPUT:-}"

emit_output() {
  if [ -n "$output_file" ]; then
    printf 'commit_created=%s\n' "$1" >>"$output_file"
  fi
}

if ! [[ "$threshold_days" =~ ^[0-9]+$ ]] || [ "$threshold_days" -le 0 ]; then
  echo "KEEPALIVE_AFTER_DAYS must be a positive integer." >&2
  exit 1
fi

if ! [[ "$now_epoch" =~ ^[0-9]+$ ]]; then
  echo "KEEPALIVE_NOW_EPOCH must be a non-negative integer." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

last_commit_ts="$(git log -1 --format=%ct "$base_ref")"
if [ -z "$last_commit_ts" ]; then
  echo "Unable to determine the latest commit time for $base_ref." >&2
  exit 1
fi

age_seconds=$((now_epoch - last_commit_ts))
if [ "$age_seconds" -lt 0 ]; then
  age_seconds=0
fi
age_days=$((age_seconds / 86400))
echo "Latest default-branch activity is ${age_days} day(s) old."

if [ "$age_days" -lt "$threshold_days" ]; then
  echo "Recent repository activity detected; keepalive not needed."
  emit_output false
  exit 0
fi

mkdir -p "$(dirname "$keepalive_file")"
printf 'Last automated keepalive: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >"$keepalive_file"
git add -- "$keepalive_file"

if git diff --cached --quiet -- "$keepalive_file"; then
  echo "Keepalive file already up to date."
  emit_output false
  exit 0
fi

git -c user.name="${KEEPALIVE_GIT_NAME:-github-actions[bot]}" \
  -c user.email="${KEEPALIVE_GIT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}" \
  commit -m "chore: keep scheduled workflows active" -- "$keepalive_file"

emit_output true
