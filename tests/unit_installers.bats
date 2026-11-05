#!/usr/bin/env bats
#
# install.sh / uninstall.sh (curl one-liners) and scripts/postinstall.sh /
# scripts/preuninstall.sh (npm hooks) are independent implementations of the
# same contract, so every test runs against both members of a pair. HOME is
# a throwaway dir; install.sh's downloads go through a curl shim that copies
# the files from this checkout.

load 'test_helper'

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CMD='~/.claude/statusline.sh'

setup() {
  T="$(mktemp -d)"
  mkdir -p "$T/bin"
  cat >"$T/bin/curl" <<EOF
#!/bin/bash
out="" url=""
while [ \$# -gt 0 ]; do
  case \$1 in
    -o) out=\$2; shift 2 ;;
    -*) shift ;;
    *)  url=\$1; shift ;;
  esac
done
cp "$REPO_ROOT/\${url##*/}" "\$out"
EOF
  chmod +x "$T/bin/curl"
}

teardown() {
  rm -rf "$T"
}

fresh_home() {
  rm -rf "$T/home"
  mkdir -p "$T/home/.claude"
  CLAUDE="$T/home/.claude"
  SETTINGS="$CLAUDE/settings.json"
}

run_installer() {
  case $1 in
    curl) HOME="$T/home" PATH="$T/bin:$PATH" bash "$REPO_ROOT/install.sh" ;;
    npm)  HOME="$T/home" bash "$REPO_ROOT/scripts/postinstall.sh" ;;
  esac >/dev/null
}

run_uninstaller() {
  case $1 in
    curl) HOME="$T/home" bash "$REPO_ROOT/uninstall.sh" ;;
    npm)  HOME="$T/home" bash "$REPO_ROOT/scripts/preuninstall.sh" ;;
  esac >/dev/null
}

settings() {
  jq -cS "${1:-.}" "$SETTINGS"
}

@test "installers: fresh install writes the statusLine command object Claude Code reads" {
  for i in curl npm; do
    fresh_home
    run_installer "$i"
    [ "$(settings .statusLine)" = '{"command":"~/.claude/statusline.sh","type":"command"}' ] || { echo "$i: $(settings)"; false; }
    [ "$(settings 'has("statusline")')" = false ]
  done
}

@test "installers: legacy lowercase statusline key is replaced and other settings are kept" {
  for i in curl npm; do
    fresh_home
    printf '{"statusline":"%s","model":"opus"}' "$CMD" >"$SETTINGS"
    run_installer "$i"
    [ "$(settings)" = '{"model":"opus","statusLine":{"command":"~/.claude/statusline.sh","type":"command"}}' ] || { echo "$i: $(settings)"; false; }
  done
}

@test "installers: existing statusLine padding and refreshInterval survive reinstall" {
  for i in curl npm; do
    fresh_home
    echo '{"statusLine":{"type":"command","command":"/old.sh","padding":1,"refreshInterval":2}}' >"$SETTINGS"
    run_installer "$i"
    [ "$(settings .statusLine)" = '{"command":"~/.claude/statusline.sh","padding":1,"refreshInterval":2,"type":"command"}' ] || { echo "$i: $(settings)"; false; }
  done
}

@test "installers: a user's own statusline.sh is backed up before being replaced" {
  for i in curl npm; do
    fresh_home
    printf '#!/bin/bash\necho mine\n' >"$CLAUDE/statusline.sh"
    run_installer "$i"
    backups=("$CLAUDE"/statusline.sh.backup-*)
    [ "${#backups[@]}" -eq 1 ] && [ -f "${backups[0]}" ] || { echo "$i: no backup"; false; }
    grep -q '^echo mine$' "${backups[0]}"
    cmp -s "$REPO_ROOT/statusline.sh" "$CLAUDE/statusline.sh"
  done
}

@test "installers: upgrading over claude-statusline's own statusline.sh makes no backup" {
  for i in curl npm; do
    fresh_home
    cp "$REPO_ROOT/statusline.sh" "$CLAUDE/statusline.sh"
    echo '# older version' >>"$CLAUDE/statusline.sh"
    run_installer "$i"
    ! compgen -G "$CLAUDE/statusline.sh.backup-*" >/dev/null || { echo "$i: unexpected backup"; false; }
    cmp -s "$REPO_ROOT/statusline.sh" "$CLAUDE/statusline.sh"
  done
}

@test "uninstallers: remove the script, its statusLine, and the legacy key; keep other settings" {
  for i in curl npm; do
    for cmd in "$CMD" "$T/home/.claude/statusline.sh"; do
      fresh_home
      cp "$REPO_ROOT/statusline.sh" "$CLAUDE/statusline.sh"
      jq -n --arg c "$cmd" '{statusLine: {type: "command", command: $c}, statusline: "~/.claude/statusline.sh", model: "opus"}' >"$SETTINGS"
      run_uninstaller "$i"
      [ ! -e "$CLAUDE/statusline.sh" ] || { echo "$i: script left behind"; false; }
      [ "$(settings)" = '{"model":"opus"}' ] || { echo "$i ($cmd): $(settings)"; false; }
    done
  done
}

@test "uninstallers: keep a user's own statusline.sh and the statusLine that runs it" {
  for i in curl npm; do
    fresh_home
    printf '#!/bin/bash\necho mine\n' >"$CLAUDE/statusline.sh"
    printf '{"statusLine":{"type":"command","command":"%s"},"statusline":"%s"}' "$CMD" "$CMD" >"$SETTINGS"
    run_uninstaller "$i"
    grep -q '^echo mine$' "$CLAUDE/statusline.sh" || { echo "$i: script removed"; false; }
    [ "$(settings)" = '{"statusLine":{"command":"~/.claude/statusline.sh","type":"command"}}' ] || { echo "$i: $(settings)"; false; }
  done
}

@test "uninstallers: keep a statusLine that points at a different script" {
  for i in curl npm; do
    fresh_home
    cp "$REPO_ROOT/statusline.sh" "$CLAUDE/statusline.sh"
    echo '{"statusLine":{"type":"command","command":"/opt/other.sh"}}' >"$SETTINGS"
    run_uninstaller "$i"
    [ "$(settings .statusLine.command)" = '"/opt/other.sh"' ] || { echo "$i: $(settings)"; false; }
  done
}
