#!/usr/bin/env bats
#
# Git status enhancement (dirty indicator, ahead/behind) — uses real
# throwaway git repos so behavior is verified against actual git plumbing,
# not a mock. Each test builds its own bare "origin" + clone under a tmpdir
# and cleans it up afterward.

load 'test_helper'

JSON='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"}}'

# Builds work/ directly (not via `git clone`) and explicitly names the
# branch "main", so the test doesn't depend on the machine's
# init.defaultBranch / clone-of-empty-repo behavior.
setup_repo_with_upstream() {
  local base="$1"
  git init --quiet --bare "$base/origin.git"
  git init --quiet -b main "$base/work"
  git -C "$base/work" config user.email "test@example.com"
  git -C "$base/work" config user.name "Test"
  git -C "$base/work" remote add origin "$base/origin.git"
  echo "one" >"$base/work/file.txt"
  git -C "$base/work" add file.txt
  git -C "$base/work" commit --quiet -m "initial"
  git -C "$base/work" push --quiet -u origin main
}

@test "golden: clean repo with upstream up to date shows plain branch name" {
  base="$(mktemp -d)"
  setup_repo_with_upstream "$base"

  run run_statusline_in "$base/work" "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"  main  │"* ]]

  rm -rf "$base"
}

@test "golden: dirty working tree appends * to the branch name" {
  base="$(mktemp -d)"
  setup_repo_with_upstream "$base"
  echo "uncommitted change" >>"$base/work/file.txt"

  run run_statusline_in "$base/work" "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"  main*  │"* ]]

  rm -rf "$base"
}

@test "golden: untracked file also counts as dirty" {
  base="$(mktemp -d)"
  setup_repo_with_upstream "$base"
  echo "new" >"$base/work/untracked.txt"

  run run_statusline_in "$base/work" "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"  main*  │"* ]]

  rm -rf "$base"
}

@test "golden: local commits ahead of upstream show an up-arrow count" {
  base="$(mktemp -d)"
  setup_repo_with_upstream "$base"
  echo "two" >>"$base/work/file.txt"
  git -C "$base/work" commit --quiet -am "second"
  echo "three" >>"$base/work/file.txt"
  git -C "$base/work" commit --quiet -am "third"

  run run_statusline_in "$base/work" "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"  main ↑2  │"* ]]

  rm -rf "$base"
}

@test "golden: commits fetched from upstream but not merged show a down-arrow count" {
  base="$(mktemp -d)"
  setup_repo_with_upstream "$base"

  git clone --quiet -b main "$base/origin.git" "$base/other"
  git -C "$base/other" config user.email "test@example.com"
  git -C "$base/other" config user.name "Test"
  echo "from elsewhere" >>"$base/other/file.txt"
  git -C "$base/other" commit --quiet -am "from another clone"
  git -C "$base/other" push --quiet origin main
  git -C "$base/work" fetch --quiet origin

  run run_statusline_in "$base/work" "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"  main ↓1  │"* ]]

  rm -rf "$base"
}

# Regression test for the intermittent "statusline hangs for a long time"
# report: a stuck git subprocess (e.g. contended index.lock, slow/network
# filesystem) must not block the whole render indefinitely. Simulates this
# with a fake `git` that always sleeps, placed first on PATH.
@test "regression: a hanging git command times out instead of blocking the render" {
  base="$(mktemp -d)"
  mkdir -p "$base/fakebin" "$base/work"
  cat >"$base/fakebin/git" <<'EOF'
#!/bin/bash
sleep 10
EOF
  chmod +x "$base/fakebin/git"

  start=$(date +%s)
  run run_statusline_in "$base/work" "$JSON" "PATH=$base/fakebin:$PATH"
  end=$(date +%s)
  elapsed=$(( end - start ))

  [ "$status" -eq 0 ]
  # Bounded well under the fake git's 10s sleep - proves the timeout fired
  # instead of the script waiting on the hung subprocess.
  [ "$elapsed" -lt 6 ]

  line1="$(sed -n '1p' <<<"$output")"
  # No branch segment was resolved in time -> graceful degradation, same as
  # the "no git repo" case (dir goes straight into the "│" separator).
  [[ "$line1" == *"/tmp/proj  │ Opus 4.6"* ]]

  rm -rf "$base"
}
