#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keepalive_script="$repo_root/scripts/keep_workflows_active.sh"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

init_repo() {
  local path="$1"
  local commit_epoch="$2"
  local include_keepalive="$3"

  git init -q -b main "$path"
  (
    cd "$path"
    printf 'fixture\n' >README.md
    if [ "$include_keepalive" = "true" ]; then
      mkdir -p .github
      printf 'Last automated keepalive: existing\n' >.github/workflow-keepalive
    fi
    git add .
    GIT_AUTHOR_DATE="@${commit_epoch}" \
      GIT_COMMITTER_DATE="@${commit_epoch}" \
      git -c user.name="Test User" -c user.email="test@example.com" \
      commit -qm "fixture"
  )
}

test_missing_keepalive_is_committed() {
  local repo="$tmp_root/missing"
  local initial_epoch=1704067200
  local now_epoch=$((initial_epoch + 46 * 86400))
  local output_file="$tmp_root/missing-output"

  init_repo "$repo" "$initial_epoch" false
  (
    cd "$repo"
    before="$(git rev-parse HEAD)"
    GITHUB_OUTPUT="$output_file" \
      KEEPALIVE_NOW_EPOCH="$now_epoch" \
      KEEPALIVE_AFTER_DAYS=45 \
      "$keepalive_script"
    after="$(git rev-parse HEAD)"

    [ "$before" != "$after" ] || fail "missing keepalive did not create a commit"
    git ls-files --error-unmatch .github/workflow-keepalive >/dev/null ||
      fail "missing keepalive was not tracked"
    assert_eq "chore: keep scheduled workflows active" \
      "$(git log -1 --format=%s)" \
      "unexpected keepalive commit subject"
    assert_eq "" "$(git status --porcelain)" "repository is dirty after keepalive commit"
    assert_eq "commit_created=true" "$(tail -n 1 "$output_file")" \
      "missing keepalive output is incorrect"
  )
}

test_recent_keepalive_is_unchanged() {
  local repo="$tmp_root/recent"
  local initial_epoch=1704067200
  local now_epoch=$((initial_epoch + 10 * 86400))
  local output_file="$tmp_root/recent-output"

  init_repo "$repo" "$initial_epoch" true
  (
    cd "$repo"
    before="$(git rev-parse HEAD)"
    before_content="$(cat .github/workflow-keepalive)"
    GITHUB_OUTPUT="$output_file" \
      KEEPALIVE_NOW_EPOCH="$now_epoch" \
      KEEPALIVE_AFTER_DAYS=45 \
      "$keepalive_script"

    assert_eq "$before" "$(git rev-parse HEAD)" \
      "recent activity unexpectedly created a commit"
    assert_eq "$before_content" "$(cat .github/workflow-keepalive)" \
      "recent keepalive file was modified"
    assert_eq "" "$(git status --porcelain)" \
      "recent repository is dirty after no-op"
    assert_eq "commit_created=false" "$(tail -n 1 "$output_file")" \
      "recent keepalive output is incorrect"
  )
}

test_missing_keepalive_is_committed
test_recent_keepalive_is_unchanged
echo "keep_workflows_active tests passed"
