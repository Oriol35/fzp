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

# Loads fzp's functions into the test, as bin/fzp would, without WSL detection or Windows programs from
# this machine
load_fzp() {
  FZP_LIB="$root/lib/fzp"
  FZP_SELF="$root/bin/fzp"
  local f
  for f in "$root"/lib/fzp/*.sh; do source "$f"; done
  fzp_wsl_interop=/nonexistent
  fzp_windows_system32=/nonexistent
}

# ---------------------------------------------------------------------------------------------------------------
# Commands

test_help_runs() {
  local out
  out="$("$root/bin/fzp" help)"
  assert_contains "$out" "fzp add"
}

test_version() {
  assert_eq "fzp 0.1.0" "$("$root/bin/fzp" --version)"
  assert_eq "fzp 0.1.0" "$("$root/bin/fzp" -V)"
}

test_help_shows_folders() {
  write_raw_config 'templates_dir = ~/t'
  mkdir -p "$HOME/t/a" && printf '# x\ny\n' >"$HOME/t/a/x.md"
  local out
  out="$("$root/bin/fzp" --help)"
  assert_contains "$out" "fzp uninstall"
  assert_contains "$out" "Config file:      ~/.config/fzp/config"$'\n'
  assert_contains "$out" "Templates folder: ~/t (1 template)"
}

test_help_without_config() {
  local out
  out="$("$root/bin/fzp" -h)"
  assert_contains "$out" "~/.config/fzp/config (not created yet)"
  assert_contains "$out" "Templates folder: ~/.local/share/fzp (0 templates)"
}

test_unknown_command() {
  local status=0
  "$root/bin/fzp" nope 2>/dev/null || status=$?
  assert_eq 1 "$status"
}

test_completion() {
  source "$root/share/bash-completion/completions/fzp"
  COMP_WORDS=(fzp un) COMP_CWORD=1
  _fzp
  assert_eq uninstall "${COMPREPLY[*]}"
  COMP_WORDS=(fzp -) COMP_CWORD=1
  _fzp
  assert_eq "-h --help -V --version" "${COMPREPLY[*]}"
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

test_clipboard_wsl_without_windows_path() {
  export WSL_DISTRO_NAME=Test
  load_fzp
  mkdir -p "$HOME/win"
  mv "$HOME/stubs/clip.exe" "$HOME/win/clip.exe"
  fzp_windows_system32="$HOME/win"
  assert_eq "$HOME/win/clip.exe" "$(clipboard_tool)"
  printf 'x' | copy_to_clipboard
  printf 'x' | iconv -f UTF-8 -t UTF-16LE | cmp - "$HOME/clipboard"
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
# Picker

# Copies the template made of the bytes $1 and compares the clipboard with the bytes $2
check_copy() {
  export WAYLAND_DISPLAY=w
  load_fzp
  printf "$1" >"$HOME/template.md"
  copy_template "$HOME/template.md"
  printf "$2" | cmp - "$HOME/clipboard"
}

test_copy_template_exact() { check_copy '# d\n\n\nbody\n\n\n' 'body\n\n\n'; }
test_copy_template_no_final_newline() { check_copy '# d\nlast' 'last'; }
test_copy_template_crlf() { check_copy '# d\r\n\r\nx\r\n' 'x\r\n'; }

test_tabs_with_spaces() {
  load_fzp
  mkdir -p "$HOME/t/My Prompts" "$HOME/t/cmds" && cd "$HOME/t"
  FZP_TAB="$HOME/tab"
  echo "My Prompts" >"$FZP_TAB"
  local out
  out="$(tabs)"
  assert_contains "$out" $'46m My Prompts \e[0m'
  assert_not_contains "$out" ' My '$'\e[0m'
}

test_cycle_with_spaces() {
  load_fzp
  mkdir -p "$HOME/t/a b" "$HOME/t/c" && cd "$HOME/t"
  FZP_TAB="$HOME/tab"
  echo all >"$FZP_TAB"
  cycle 1
  assert_eq "a b" "$(<"$FZP_TAB")"
  cycle 1
  assert_eq c "$(<"$FZP_TAB")"
  cycle 1
  assert_eq all "$(<"$FZP_TAB")"
  cycle -1
  assert_eq c "$(<"$FZP_TAB")"
}

test_fzf_check() {
  load_fzp
  fzf_check fzf
  stub_old_fzf
  local out status=0
  out="$(fzf_check fzf)" || status=$?
  assert_eq 1 "$status" status
  assert_contains "$out" freeze-left
}

test_fzf_missing_message() {
  rm "$HOME/stubs/fzf"
  mkdir -p "$HOME/.local/share/fzp/a" && printf '# x\ny\n' >"$HOME/.local/share/fzp/a/x.md"
  local out status=0
  out="$("$root/bin/fzp" 2>&1)" || status=$?
  assert_eq 1 "$status" status
  assert_contains "$out" "Run the fzp installer again"
}

# ---------------------------------------------------------------------------------------------------------------
# fzp add

test_slugify() {
  load_fzp
  assert_eq traduccio-nandu "$(printf 'Traducció Ñandú' | slugify)"
  local out
  out="$(printf 'a\xffb' | slugify)"
  [[ -n "$out" ]] || flunk "slugify of invalid UTF-8 is empty"
}

test_resolve_category() {
  load_fzp
  mkdir -p "$HOME/t/My Prompts" && cd "$HOME/t"
  assert_eq "My Prompts" "$(resolve_category "My Prompts")"
  assert_eq new-stuff "$(resolve_category "New Stuff")"
  assert_eq "" "$(resolve_category '!!!')"
  assert_eq all "$(resolve_category all)" "slug of all (add rejects it)"
}

test_split_file_name() {
  load_fzp
  assert_eq $'deploy-notes\tmd' "$(split_file_name "Deploy Notes")"
  assert_eq $'backup\tsh' "$(split_file_name backup.SH)"
  assert_eq $'v1-2-notes\ttxt' "$(split_file_name v1.2.notes.txt)"
  assert_eq $'name\tmd' "$(split_file_name name.)"
}

test_name_taken() {
  load_fzp
  mkdir -p "$HOME/t/cmds" && cd "$HOME/t"
  printf '# x\n' >cmds/x.sh
  printf '# x.y\n' >cmds/x.y.md
  assert_eq cmds/x.sh "$(name_taken cmds x)"
  assert_eq cmds/x.y.md "$(name_taken cmds x.y)"
  name_taken cmds y && flunk "y isn't taken"
  return 0
}

# ---------------------------------------------------------------------------------------------------------------
# fzp config

# ~/old with three templates, a binary file and a loose file; "~/new space" already has a/two.md
make_move_fixture() {
  mkdir -p "$HOME/old/a" "$HOME/old/b" "$HOME/new space/a"
  printf '# one\n1\n' >"$HOME/old/a/one.md"
  printf '# two\n2\n' >"$HOME/old/a/two.md"
  printf '# three\n3\n' >"$HOME/old/b/three.txt"
  printf '# run\necho hi\n' >"$HOME/old/b/run.sh"
  printf '%%PDF\x00' >"$HOME/old/a/notes.pdf"
  printf 'loose\n' >"$HOME/old/README"
  printf '# two, already here\n' >"$HOME/new space/a/two.md"
}

test_left_behind() {
  load_fzp
  make_move_fixture
  assert_eq "$(printf '%s\n' README a/notes.pdf a/two.md | sort)" \
    "$(templates_left_behind "$HOME/old" "$HOME/new space")"
}

test_move_templates() {
  load_fzp
  make_move_fixture
  move_templates "$HOME/old" "$HOME/new space" >/dev/null
  assert_file "$HOME/new space/a/one.md"
  assert_file "$HOME/new space/b/three.txt"
  assert_file "$HOME/new space/b/run.sh"
  assert_eq "# two, already here" "$(head -n1 "$HOME/new space/a/two.md")" "kept the new folder's two.md"
  assert_file "$HOME/old/a/two.md"
  assert_file "$HOME/old/README"
  assert_no_file "$HOME/old/b"
}

test_move_everything_removes_old() {
  load_fzp
  mkdir -p "$HOME/old/a"
  printf '# one\n1\n' >"$HOME/old/a/one.md"
  move_templates "$HOME/old" "$HOME/new" >/dev/null
  assert_file "$HOME/new/a/one.md"
  assert_no_file "$HOME/old"
  assert_eq "" "$(templates_left_behind "$HOME/new" "$HOME/other")" "nothing would stay behind"
}

test_config_without_terminal() {
  local out status=0
  out="$("$root/bin/fzp" config </dev/null 2>&1)" || status=$?
  assert_eq 1 "$status" "status without a config file"
  assert_contains "$out" 'Run "fzp config" in a terminal'
  write_raw_config 'templates_dir = ~/t'
  out="$("$root/bin/fzp" config </dev/null)"
  assert_eq "$HOME/.config/fzp/config" "$out"
}

# ---------------------------------------------------------------------------------------------------------------
# fzp uninstall

# What an install leaves in ~: fzp, its code, a private fzf, completion, the PATH line, config and templates
make_fake_install() {
  mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/fzp" "$HOME/.local/share/bash-completion/completions"
  cp "$root/bin/fzp" "$HOME/.local/bin/fzp"
  cp "$root"/lib/fzp/*.sh "$HOME/.local/lib/fzp/"
  printf '#!/bin/sh\n' >"$HOME/.local/lib/fzp/fzf"
  cp "$root/share/bash-completion/completions/fzp" "$HOME/.local/share/bash-completion/completions/fzp"
  printf '%s\n' 'export A=1' '# Added by the fzp installer' 'export PATH="$HOME/.local/bin:$PATH"' 'export B=2' \
    >"${1:-$HOME/.bashrc}"
  write_raw_config 'templates_dir = ~/t'
  mkdir -p "$HOME/t/a" && printf '# x\ny\n' >"$HOME/t/a/x.md"
}

test_uninstall_defaults() {
  make_fake_install
  local out
  out="$("$root/bin/fzp" uninstall </dev/null)"
  assert_no_file "$HOME/.local/bin/fzp"
  assert_no_file "$HOME/.local/lib/fzp"
  assert_no_file "$HOME/.local/lib"
  assert_no_file "$HOME/.local/share/bash-completion"
  assert_file "$HOME/.local/bin"
  assert_eq $'export A=1\nexport B=2' "$(<"$HOME/.bashrc")" ".bashrc"
  assert_file "$HOME/.bashrc.fzp-backup"
  assert_file "$HOME/.config/fzp/config"
  assert_file "$HOME/t/a/x.md"
  assert_contains "$out" "~/.config/fzp/config"
  assert_contains "$out" "~/t (1 template)"
}

test_uninstall_bashrc_symlink() {
  mkdir -p "$HOME/dotfiles"
  make_fake_install "$HOME/dotfiles/bashrc"
  ln -s "$HOME/dotfiles/bashrc" "$HOME/.bashrc"
  "$root/bin/fzp" uninstall </dev/null >/dev/null
  [[ -L "$HOME/.bashrc" ]] || flunk ".bashrc isn't a symlink any more"
  assert_eq $'export A=1\nexport B=2' "$(<"$HOME/dotfiles/bashrc")" "dotfiles/bashrc"
}

test_uninstall_leaves_other_fzp() {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\necho another tool\n' >"$HOME/.local/bin/fzp"
  "$root/bin/fzp" uninstall </dev/null >/dev/null
  assert_file "$HOME/.local/bin/fzp"
}

# ---------------------------------------------------------------------------------------------------------------
# Installer

# Runs the installer from this checkout without a terminal, so every question takes its default
run_installer() { "$root/install.sh" </dev/null 2>&1; }

# How many example templates the repo ships
example_count() { find "$root/examples" -mindepth 2 -maxdepth 2 -type f 2>/dev/null | wc -l; }

test_install_fresh() {
  printf 'export A=1\n' >"$HOME/.bashrc"
  run_installer >"$HOME/out" || { cat "$HOME/out"; flunk "installer failed"; }
  assert_file "$HOME/.local/bin/fzp"
  assert_file "$HOME/.local/lib/fzp/common.sh"
  assert_file "$HOME/.local/share/bash-completion/completions/fzp"
  assert_eq "fzp 0.1.0" "$("$HOME/.local/bin/fzp" --version)"
  assert_contains "$(<"$HOME/.config/fzp/config")" "templates_dir = ~/.local/share/fzp"
  assert_eq "$(example_count)" "$(find "$HOME/.local/share/fzp" -mindepth 2 -type f | wc -l)" "examples copied"
  assert_eq 1 "$(grep -c '^# Added by the fzp installer$' "$HOME/.bashrc")" "marker lines"
  assert_eq 'export A=1' "$(head -n1 "$HOME/.bashrc")"
  assert_eq 'export A=1' "$(<"$HOME/.bashrc.fzp-backup")" "backup"
  assert_no_file "$HOME/.local/lib/fzp/fzf"
  assert_contains "$(<"$HOME/out")" 'Open a new terminal'
}

test_install_twice() {
  run_installer >/dev/null
  write_raw_config 'templates_dir = ~/mine'
  local out
  out="$(run_installer)"
  assert_contains "$out" "Update fzp 0.1.0 to 0.1.0"
  assert_not_contains "$out" "Where should your templates live"
  assert_eq "templates_dir = ~/mine" "$(<"$HOME/.config/fzp/config")" "config kept"
  assert_eq 1 "$(grep -c '^# Added by the fzp installer$' "$HOME/.bashrc")" "marker lines"
}

test_install_keeps_private_fzf() {
  run_installer >/dev/null
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/lib/fzp/fzf"
  chmod +x "$HOME/.local/lib/fzp/fzf"
  rm "$HOME/stubs/fzf"
  run_installer >/dev/null
  assert_file "$HOME/.local/lib/fzp/fzf"
}

test_install_bashrc_symlink() {
  mkdir -p "$HOME/dotfiles"
  printf 'export A=1' >"$HOME/dotfiles/bashrc"
  ln -s "$HOME/dotfiles/bashrc" "$HOME/.bashrc"
  run_installer >/dev/null
  [[ -L "$HOME/.bashrc" ]] || flunk ".bashrc isn't a symlink any more"
  assert_eq $'export A=1\n# Added by the fzp installer' "$(head -n2 "$HOME/dotfiles/bashrc")" \
    "line added after a last line without a newline"
}

test_install_other_fzp_stops() {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\necho another tool\n' >"$HOME/.local/bin/fzp"
  chmod +x "$HOME/.local/bin/fzp"
  local status=0 out
  out="$(run_installer)" || status=$?
  assert_eq 1 "$status" status
  assert_contains "$out" "isn't fzp"
  assert_eq "another tool" "$("$HOME/.local/bin/fzp")"
}

test_install_old_fzf_unsupported_cpu() {
  stub_old_fzf
  stub uname 'echo riscv64'
  local out
  out="$(run_installer)"
  assert_contains "$out" "too old"
  assert_contains "$out" "riscv64"
  assert_file "$HOME/.local/bin/fzp"
  assert_no_file "$HOME/.local/lib/fzp/fzf"
}

test_install_fzf_download() {
  [[ "${FZP_TEST_NETWORK:-}" == 1 ]] || skip_test "needs FZP_TEST_NETWORK=1"
  rm "$HOME/stubs/fzf"
  run_installer >"$HOME/out" || { cat "$HOME/out"; flunk "installer failed"; }
  assert_eq "0.74.5" "$("$HOME/.local/lib/fzp/fzf" --version | cut -d' ' -f1)"
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
