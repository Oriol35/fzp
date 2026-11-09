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

fail() { printf '    %s\n' "$@" >&2; return 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "${3:-value}: expected [$1]" "got      [$2]"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected to find [$2] in:" "$1"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "expected not to find [$2] in:" "$1"; }
assert_file() { [[ -e "$1" || -L "$1" ]] || fail "missing: $1"; }
assert_no_file() { [[ ! -e "$1" && ! -L "$1" ]] || fail "should not exist: $1"; }
# Ends the current test as skipped
skip() { echo "$1"; exit 200; }

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
