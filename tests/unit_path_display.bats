#!/usr/bin/env bats
#
# Unit tests for the Line 1 directory helpers: _home_tilde (anchored $HOME
# -> ~ substitution), _abbrev_path (progressive fish-style shortening) and
# _file_url (OSC 8 file:// target, percent-encoded).

load 'test_helper'

setup() {
  load_fn _home_tilde
  load_fn _abbrev_path
  load_fn _file_url
}

# ---- _home_tilde ----

@test "_home_tilde replaces only a leading \$HOME followed by / or end" {
  HOME=/Users/me
  _home_tilde /Users/me;             [ "$REPLY" = "~" ]
  _home_tilde /Users/me/proj;        [ "$REPLY" = "~/proj" ]
}

@test "regression: _home_tilde leaves a sibling dir sharing the \$HOME prefix alone" {
  HOME=/Users/me
  _home_tilde /Users/meow/proj
  [ "$REPLY" = "/Users/meow/proj" ]
}

@test "regression: _home_tilde does not rewrite a \$HOME string appearing mid-path" {
  HOME=/Users/me
  _home_tilde /mnt/Users/me/proj
  [ "$REPLY" = "/mnt/Users/me/proj" ]
}

@test "_home_tilde is a no-op when HOME is empty or /" {
  HOME=""; _home_tilde /tmp/x; [ "$REPLY" = "/tmp/x" ]
  HOME=/;  _home_tilde /tmp/x; [ "$REPLY" = "/tmp/x" ]
}

# ---- _abbrev_path ----

@test "_abbrev_path returns the path unchanged when it fits" {
  _abbrev_path "~/personal/claude-statusline" 32 ""
  [ "$REPLY" = "~/personal/claude-statusline" ]
}

@test "_abbrev_path max=0 or non-numeric disables abbreviation" {
  local long="~/work/mobidoc/mobidoc-server/src/main/java/us/api"
  _abbrev_path "$long" 0 "";   [ "$REPLY" = "$long" ]
  _abbrev_path "$long" abc ""; [ "$REPLY" = "$long" ]
}

@test "_abbrev_path shortens middle segments left to right only as far as needed" {
  # 49 chars; shortening work, mobidoc, mobidoc-server brings it to 28 --
  # src/main/java stay whole because it already fits
  _abbrev_path "~/work/mobidoc/mobidoc-server/src/main/java/us/api" 32 ""
  [ "$REPLY" = "~/w/m/m/src/main/java/us/api" ]
}

@test "_abbrev_path keeps the project_dir segment whole" {
  _abbrev_path "~/work/mobidoc/mobidoc-server/src/main/java/us/api" 32 "~/work/mobidoc/mobidoc-server"
  [ "$REPLY" = "~/w/m/mobidoc-server/s/m/j/u/api" ]
}

@test "_abbrev_path drops everything before project_dir when shortening alone overflows" {
  # fully shortened form /s/w/m/mobidoc-server/s/m/j/u/api is 33 chars
  _abbrev_path "/srv/work/mobidoc/mobidoc-server/src/main/java/us/api" 32 "/srv/work/mobidoc/mobidoc-server"
  [ "$REPLY" = "…/mobidoc-server/s/m/j/u/api" ]
}

@test "_abbrev_path leaves a non-ASCII segment whole under a non-UTF-8 locale" {
  LC_ALL=C
  # C locale counts bytes: the Korean segment is 15, the shortened path 30
  _abbrev_path "/aaaa/안녕하세요/bbbb/cccc/leaf" 30 ""
  [ "$REPLY" = "/a/안녕하세요/b/cccc/leaf" ]
}

@test "_abbrev_path ignores an anchor the path is not inside" {
  _abbrev_path "~/work/mobidoc/mobidoc-server/src/main/java/us/api" 32 "~/work/mobidoc/mobidoc-serverX"
  [[ "$REPLY" != *"mobidoc-server/"* ]]
}

@test "_abbrev_path keeps the leading dot of hidden segments" {
  _abbrev_path "~/.config/something-long/nvim/lua/plugins" 24 ""
  [ "$REPLY" = "~/.c/s/nvim/lua/plugins" ]
}

@test "_abbrev_path never shortens the last segment" {
  _abbrev_path "/var/lib/a-really-long-leaf-directory-name" 20 ""
  [[ "$REPLY" == *"a-really-long-leaf-directory-name" ]]
}

@test "_abbrev_path falls back to …/ + the longest whole tail that fits" {
  # Even fully shortened (~/a/b/c/d/e/f/g/h/i/project-name-x) exceeds 20
  _abbrev_path "~/aa/bb/cc/dd/ee/ff/gg/hh/ii/jj/project-name-x/src" 20 "~/aa/bb/cc/dd/ee/ff/gg/hh/ii/jj/project-name-x"
  [ "$REPLY" = "…/project-name-x/src" ]
}

@test "_abbrev_path tail fallback still shows an over-long leaf whole" {
  _abbrev_path "/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/leaf-that-alone-is-too-long" 10 ""
  [ "$REPLY" = "…/leaf-that-alone-is-too-long" ]
}

@test "_abbrev_path handles absolute (non-home) paths" {
  _abbrev_path "/usr/local/share/very-long-name/subdir" 25 ""
  [ "$REPLY" = "/u/l/s/v/subdir" ]
}

# ---- _file_url ----

@test "_file_url builds file://<host><path> for a plain path" {
  HOSTNAME=mac
  _file_url /tmp/proj/my_app-1.0
  [ "$REPLY" = "file://mac/tmp/proj/my_app-1.0" ]
}

@test "_file_url percent-encodes spaces and reserved characters" {
  HOSTNAME=mac
  _file_url "/tmp/a b/#c?d%e"
  [ "$REPLY" = "file://mac/tmp/a%20b/%23c%3Fd%25e" ]
}

@test "regression: _file_url encodes multibyte (Korean) bytes as positive hex on every bash" {
  # bash 3.2's printf "'<byte>" yields a negative value for bytes >= 0x80
  HOSTNAME=mac
  _file_url "/tmp/안"
  [ "$REPLY" = "file://mac/tmp/%EC%95%88" ]
}

@test "_file_url returns empty for a non-absolute path" {
  HOSTNAME=mac
  _file_url "unknown";   [ -z "$REPLY" ]
  _file_url 'C:\Users\x'; [ -z "$REPLY" ]
}
