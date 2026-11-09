#!/usr/bin/env bash
# fzp's tests: plain bash, no framework. Each test_* function runs in its own subshell, with a throwaway
# HOME, stand-in fzf and clipboard tools on PATH, and none of your own settings.
#   tests/smoke.sh            run every test
#   tests/smoke.sh PATTERN    run the tests whose name matches PATTERN (an extended regex)
# The tests that download from the internet only run with FZP_TEST_NETWORK=1.
set -uo pipefail

root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"

# ---------------------------------------------------------------------------------------------------------------
# Helpers

flunk() { printf '    %s\n' "$@" >&2; return 1; }
assert_eq() { [[ "$1" == "$2" ]] || flunk "${3:-value}: expected [$1]" "got      [$2]"; }
assert_contains() { [[ "$1" == *"$2"* ]] || flunk "expected to find [$2] in:" "$1"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || flunk "expected not to find [$2] in:" "$1"; }
assert_file() { [[ -e "$1" || -L "$1" ]] || flunk "missing: $1"; }
assert_no_file() { [[ ! -e "$1" && ! -L "$1" ]] || flunk "should not exist: $1"; }
# Ends the current test as skipped
skip_test() { echo "$1"; exit 200; }

# A stand-in command $1 in the sandbox's stubs folder, running the bash code $2
stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$HOME/stubs/$1"
  chmod +x "$HOME/stubs/$1"
}
# An fzf too old for fzp: rejects the options fzp uses, the way an old fzf does
stub_old_fzf() { stub fzf 'echo "unknown option: --freeze-left" >&2; exit 2'; }

# A throwaway HOME with stand-ins: fzf accepts everything, and the clipboard tools use the file ~/clipboard
sandbox() {
  HOME="$(mktemp -d "$tmp_root/home.XXXX")"
  export HOME
  unset XDG_CONFIG_HOME XDG_DATA_HOME WSL_DISTRO_NAME WAYLAND_DISPLAY DISPLAY VISUAL EDITOR FZP_CONFIG \
    FZP_TEMPLATES_DIR
  mkdir -p "$HOME/stubs"
  stub fzf 'if [[ "${1:-}" == --version ]]; then echo "0.74.5 (stub)"; fi'
  stub wl-copy 'cat >"$HOME/clipboard"'
  stub clip.exe 'cat >"$HOME/clipboard"'
  stub wl-paste 'cat "$HOME/clipboard"'
  export PATH="$HOME/stubs:/usr/local/bin:/usr/bin:/bin"
  cd "$HOME"
}

# Loads fzp's functions into the test, as bin/fzp would, without WSL detection from this machine
load_fzp() {
  FZP_LIB="$root/lib/fzp"
  FZP_SELF="$root/bin/fzp"
  local f
  for f in "$root"/lib/fzp/*.sh; do source "$f"; done
  fzp_wsl_interop=/nonexistent
}

# ---------------------------------------------------------------------------------------------------------------
# Commands

test_help_runs() {
  local out
  out="$("$root/bin/fzp" help)"
  assert_contains "$out" "fzp add"
}

# ---------------------------------------------------------------------------------------------------------------
# Config

# Writes the config file, one argument per line
write_raw_config() {
  mkdir -p "$HOME/.config/fzp"
  printf '%s\n' "$@" >"$HOME/.config/fzp/config"
}

test_config_default() {
  load_fzp
  load_config
  assert_eq "$HOME/.local/share/fzp" "$templates_dir" templates_dir
  assert_eq 0 "${#config_problems[@]}" problems
}

test_config_reads_templates_dir() {
  write_raw_config '# comment' '' 'templates_dir = ~/My Templates/'
  load_fzp
  load_config
  assert_eq "$HOME/My Templates" "$templates_dir"
  assert_eq 0 "${#config_problems[@]}" problems
}

test_config_relative_is_from_home() {
  write_raw_config 'templates_dir = notes'
  load_fzp
  cd /tmp
  load_config
  assert_eq "$HOME/notes" "$templates_dir"
}

test_config_ignores_env() {
  mkdir -p "$HOME/other"
  printf 'templates_dir = /tmp/elsewhere\n' >"$HOME/other/config"
  export FZP_TEMPLATES_DIR=/tmp/x FZP_CONFIG="$HOME/other/config"
  load_fzp
  load_config
  assert_eq "$HOME/.local/share/fzp" "$templates_dir"
  assert_eq "$HOME/.config/fzp/config" "$config_file"
}

test_config_problems() {
  write_raw_config 'colour = red' 'templates_dir ='
  load_fzp
  load_config
  assert_eq 2 "${#config_problems[@]}" problems
  assert_contains "${config_problems[0]}" '"colour"'
  assert_contains "${config_problems[0]}" '.config/fzp/config'
  assert_contains "${config_problems[1]}" 'templates_dir'
  assert_contains "${config_problems[1]}" 'empty'
  assert_contains "${config_problems[1]}" '.config/fzp/config'
  assert_eq "$HOME/.local/share/fzp" "$templates_dir" "fallback"
}

test_write_config_roundtrip() {
  load_fzp
  load_config
  write_config "$HOME/a b"
  assert_contains "$(<"$HOME/.config/fzp/config")" 'templates_dir = ~/a b'
  load_config
  assert_eq "$HOME/a b" "$templates_dir"
  assert_eq 0 "${#config_problems[@]}" problems
}

test_ask_default_without_terminal() {
  load_fzp
  local status=0
  ask "Q?" y </dev/null || status=$?
  assert_eq 0 "$status" "default yes"
  status=0
  ask "Q?" n </dev/null || status=$?
  assert_eq 1 "$status" "default no"
}

test_no_legacy_words() {
  local found
  found="$(grep -rnE 'FZP_CONFIG|FZP_TEMPLATES_DIR|old_settings|older fzp|"library"|"height"' "$root/bin" "$root/lib" || true)"
  assert_eq "" "$found"
}

# ---------------------------------------------------------------------------------------------------------------
# Templates

# A templates folder at ~/t with three real templates and everything that must not count as one
make_fixture() {
  mkdir -p "$HOME/t" && cd "$HOME/t"
  mkdir -p "My Prompts" cmds/deep .git all
  printf '# Traducció\n\nbody\n' >"My Prompts/traducció.md"
  printf '# X\necho x\n' >cmds/x.sh
  printf '# Title\r\nbody\r\n' >cmds/crlf.txt
  printf '# nested\n' >cmds/deep/nested.md
  printf '# hidden\n' >cmds/.hidden.md
  printf '# git\n' >.git/c.md
  printf '# all\n' >all/a.md
  printf '\x89PNG\x00\x01' >cmds/logo.png
  : >cmds/empty.txt
  printf '# top\n' >top.md
}

test_categories() {
  load_fzp
  make_fixture
  assert_eq "$(printf '%s\n' cmds "My Prompts" | sort)" "$(categories)"
}

test_template_files() {
  load_fzp
  make_fixture
  assert_eq "$(printf '%s\n' cmds/crlf.txt cmds/x.sh "My Prompts/traducció.md" | sort)" "$(template_files)"
}

test_template_files_empty_folder() {
  load_fzp
  mkdir -p "$HOME/empty/cat" && cd "$HOME/empty"
  assert_eq "" "$(template_files)"
}

test_count_templates() {
  load_fzp
  make_fixture
  cd /
  assert_eq 3 "$(count_templates "$HOME/t")"
  assert_eq 0 "$(count_templates "$HOME/missing")"
}

test_template_name() {
  load_fzp
  assert_eq "b.c" "$(template_name a/b.c.md)"
  assert_eq "Makefile" "$(template_name a/Makefile)"
  assert_eq "traducció" "$(template_name "My Prompts/traducció.md")"
}

test_template_description_crlf() {
  load_fzp
  make_fixture
  assert_eq "Title" "$(template_description cmds/crlf.txt)"
  assert_eq "Traducció" "$(template_description "My Prompts/traducció.md")"
}

# ---------------------------------------------------------------------------------------------------------------
# Clipboard

test_clipboard_linux_wayland() {
  export WAYLAND_DISPLAY=w
  load_fzp
  assert_eq wl-copy "$(clipboard_tool)"
  printf 'héllo\n\n' | copy_to_clipboard
  printf 'héllo\n\n' | cmp - "$HOME/clipboard"
}

test_clipboard_wsl_prefers_clip_exe() {
  export WSL_DISTRO_NAME=Test WAYLAND_DISPLAY=w
  load_fzp
  assert_eq clip.exe "$(clipboard_tool)"
  printf 'héllo\n' | copy_to_clipboard
  printf 'héllo\n' | iconv -f UTF-8 -t UTF-16LE | cmp - "$HOME/clipboard"
}

test_clipboard_wsl_paste() {
  export WSL_DISTRO_NAME=Test
  stub powershell.exe "printf 'a\r\nb\r\n'"
  load_fzp
  paste_from_clipboard >"$HOME/pasted"
  printf 'a\nb\n' | cmp - "$HOME/pasted"
}

test_clipboard_none() {
  rm "$HOME/stubs/wl-copy" "$HOME/stubs/clip.exe"
  export WAYLAND_DISPLAY=w WSL_DISTRO_NAME=Test PATH="$HOME/stubs"
  load_fzp
  local status=0 message
  clipboard_tool >/dev/null || status=$?
  assert_eq 1 "$status" "clipboard_tool status"
  message="$(echo x | copy_to_clipboard 2>&1)" && flunk "copy_to_clipboard should fail"
  assert_contains "$message" xsel
}

# ---------------------------------------------------------------------------------------------------------------
# Runner

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
pattern="${1:-.}"
passed=0 failed=0 skipped=0
for t in $(declare -F | awk '{ print $3 }' | grep '^test_' | grep -E -- "$pattern"); do
  log="$tmp_root/$t.log"
  (
    set -e
    sandbox
    "$t"
  ) >"$log" 2>&1
  status=$?
  if (( status == 0 )); then
    printf 'ok    %s\n' "$t"
    passed=$((passed + 1))
  elif (( status == 200 )); then
    printf 'skip  %s (%s)\n' "$t" "$(tail -n1 "$log")"
    skipped=$((skipped + 1))
  else
    printf 'FAIL  %s\n' "$t"
    sed 's/^/      /' "$log"
    failed=$((failed + 1))
  fi
done
printf '\n%d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
(( failed == 0 && passed + skipped > 0 ))
