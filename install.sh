#!/usr/bin/env bash
# Installs FuzzyPaste (fzp) for the current user, by default under ~/.local: bin/fzp and
# share/bash-completion/completions/fzp (Tab completion) link back to this folder, so `git pull`
# here updates fzp. With --copy, lib/fzp/*.sh is copied too and this folder can be deleted.
# When fzp is already installed, asks whether to replace it or cancel (which changes nothing). Then
# makes sure fzp is on PATH, creates the config file and offers to copy this folder's templates.
# Every change to ~/.bashrc is asked first.
set -euo pipefail

src="$(dirname "$(realpath "$0")")"
prefix="$HOME/.local"
mode=link
bashrc="$HOME/.bashrc"
marker="# Added by the fzp installer"

usage() {
  cat <<'EOF'
Install FuzzyPaste (fzp) for your user.

  ./install.sh               install fzp into ~/.local, linked to this folder: "git pull" here updates it
  ./install.sh --copy        copy fzp instead, so this folder can be deleted afterwards
  ./install.sh --prefix DIR  install into DIR instead of ~/.local
  ./install.sh --uninstall   remove fzp, the same as ./uninstall.sh (your templates are kept)
  ./install.sh --help        show this help
EOF
}

ok() { printf '\e[32m ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[33m ⚠\e[0m %s\n' "$*"; }
die() { printf '\e[31m ✗\e[0m %s\n' "$*" >&2; exit 1; }
title() { printf '\n\e[1;36m %s\e[0m\n\n' "$*"; }

# Yes/no question; $2 is the answer Enter gives (y or n). Without a terminal nothing optional is
# changed, so the answer is always no.
ask() {
  local answer hint="[Y/n]"
  [[ "$2" == n ]] && hint="[y/N]"
  [[ -t 0 ]] || return 1
  read -r -p "   $1 $hint " answer || answer=n
  [[ "${answer:-$2}" == [yY]* ]]
}

shorten_home() {
  if [[ "$1" == "$HOME" || "$1" == "$HOME/"* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}

# $1 is what's cancelled: Install (the default) or Uninstall
cancel() {
  printf '\n   %s cancelled. Nothing was changed.\n\n' "${1:-Install}"
  exit 0
}

# Prints the first fzf option or action fzp uses that the fzf at $1 rejects (an older fzf exits
# with status 2), and fails when it accepts them all
fzf_too_old() {
  local status=0 error
  error="$("$1" --filter=x --style=full --footer=x --footer-label=x --freeze-left=1 --gutter=x \
    --ghost=x --no-input --list-label=x --input-label=x --header-first --info=inline-right \
    --tabstop=1 --no-clear --layout=reverse-list \
    --bind 'tab:transform-footer(echo),alt-enter:print-query,change:refresh-preview' \
    </dev/null 2>&1 >/dev/null)" || status=$?
  (( status == 2 )) && printf '%s' "$error"
}

# Option 1 is $1, option 2 cancels. Returns when 1 is chosen.
choose_or_cancel() {
  local answer
  printf '     1) %s\n     2) Cancel the install, without changing anything\n' "$1"
  [[ -t 0 ]] || die "Run the installer in a terminal to choose. Nothing was changed."
  while true; do
    read -r -p "   Choose [1/2]: " answer || cancel
    case "$answer" in
      1) return ;;
      2) cancel ;;
    esac
  done
}

# An fzp already on this computer: at the install location (this install replaces it), or somewhere
# else on PATH. Asks whether to go on or cancel, before anything is changed.
check_existing() {
  local where="" target other
  if [[ -L "$bin_dst" ]]; then
    target="$(readlink "$bin_dst")"
    where="$(shorten_home "$bin_dst"), linked to $(shorten_home "$(dirname "$(dirname "$target")")")"
    [[ -e "$bin_dst" ]] || where+=" (that folder is gone)"
  elif [[ -e "$bin_dst" ]]; then
    grep -qs 'FuzzyPaste' "$bin_dst" ||
      die "$(shorten_home "$bin_dst") already exists and isn't fzp, so it's left alone. Use --prefix to install elsewhere."
    where="$(shorten_home "$bin_dst")"
  fi
  if [[ -n "$where" ]]; then
    warn "fzp is already installed: $where"
    choose_or_cancel "Replace it with the fzp in $(shorten_home "$src")"
    echo
  fi

  other="$(type -P fzp || true)"
  if [[ -n "$other" && "$other" != "$bin_dst" ]]; then
    warn "There's another fzp at $(shorten_home "$other"), which this install doesn't touch."
    choose_or_cancel "Install into $(shorten_home "$prefix/bin") anyway, keeping both"
    echo
  fi
}

check_requirements() {
  local t
  (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) ||
    die "fzp needs bash 4.4 or newer (this is $BASH_VERSION)."
  for t in sed find iconv tput realpath; do
    command -v "$t" >/dev/null || die "fzp needs \"$t\", which isn't installed."
  done
  command -v fzf >/dev/null ||
    die "fzp needs fzf. Install a recent version from https://github.com/junegunn/fzf/releases"
  local error
  if error="$(fzf_too_old fzf)"; then
    die "fzf $(fzf --version | cut -d' ' -f1) is too old for fzp ($error). Install a recent version from https://github.com/junegunn/fzf/releases"
  fi
  ok "fzf $(fzf --version | cut -d' ' -f1)"

  if command -v gawk >/dev/null || awk --version 2>/dev/null | grep -q 'GNU Awk'; then
    ok "GNU awk"
  else
    warn "GNU awk isn't installed: search highlights in the preview become case-sensitive. Install \"gawk\" to fix it."
  fi
  if command -v wl-copy >/dev/null || command -v xclip >/dev/null || command -v xsel >/dev/null; then
    ok "clipboard tool"
  else
    warn "No clipboard tool found: install wl-clipboard (Wayland) or xclip (X11), or fzp can't copy."
  fi
  if [[ -f /usr/share/bash-completion/bash_completion || -f /etc/bash_completion ]]; then
    ok "bash-completion"
  else
    warn "The bash-completion package isn't installed, so Tab won't complete fzp commands."
  fi
}

# Paths of an installation under $prefix
set_paths() {
  bin_dst="$prefix/bin/fzp"
  lib_dst="$prefix/lib/fzp"
  comp_dst="$prefix/share/bash-completion/completions/fzp"
}

# Removes what a previous install put under $prefix, and nothing else called fzp
remove_installed() {
  if [[ -L "$bin_dst" ]] || grep -qs 'FuzzyPaste' "$bin_dst"; then rm -f "$bin_dst"; fi
  if [[ -L "$lib_dst" ]]; then
    rm -f "$lib_dst"
  elif [[ -f "$lib_dst/common.sh" ]]; then
    rm -rf "$lib_dst"
  fi
  if [[ -L "$comp_dst" ]] || grep -qs '_fzp' "$comp_dst"; then rm -f "$comp_dst"; fi
}

install_files() {
  remove_installed
  mkdir -p "$prefix/bin" "$(dirname "$comp_dst")"
  if [[ "$mode" == link ]]; then
    # bin/fzp finds its lib/ through the link, so only the command and completion are linked.
    # The link needs bin/fzp to be executable, which a download as a zip can lose.
    chmod +x "$src/bin/fzp"
    ln -s "$src/bin/fzp" "$bin_dst"
    ln -s "$src/share/bash-completion/completions/fzp" "$comp_dst"
    ok "Installed $(shorten_home "$bin_dst"), linked to $(shorten_home "$src")"
  else
    mkdir -p "$lib_dst"
    install -m 755 "$src/bin/fzp" "$bin_dst"
    install -m 644 "$src"/lib/fzp/*.sh "$lib_dst/"
    install -m 644 "$src/share/bash-completion/completions/fzp" "$comp_dst"
    ok "Installed $(shorten_home "$bin_dst") (a copy)"
  fi
  ok "Tab completion: $(shorten_home "$comp_dst")"
}

# fzp must be reachable on PATH
fix_shell() {
  case ":$PATH:" in
    *":$prefix/bin:"*) ok "$(shorten_home "$prefix/bin") is on PATH" ;;
    *)
      if grep -qsF "$marker" "$bashrc"; then
        ok "$(shorten_home "$prefix/bin") is added to PATH in ~/.bashrc (active in new terminals)"
      else
        warn "$(shorten_home "$prefix/bin") isn't on PATH, so the shell won't find fzp."
        if ask "Add it to PATH in ~/.bashrc?" y; then
          printf '\n%s\nexport PATH="%s:$PATH"\n' "$marker" "$prefix/bin" >>"$bashrc"
          ok "Added $(shorten_home "$prefix/bin") to PATH in ~/.bashrc"
        fi
      fi ;;
  esac
}

# Creates the config file with `fzp config` when there isn't one
setup_config() {
  local path
  if path="$("$bin_dst" config </dev/null 2>/dev/null)"; then
    ok "Config file: $(shorten_home "$path")"
    # A config file from an older fzp: `fzp config` explains what changed and offers to update it
    if "$bin_dst" help 2>&1 >/dev/null | grep -q . && [[ -t 0 ]]; then
      "$bin_dst" config || true
    fi
  else
    "$bin_dst" config || true
  fi
}

# Offers to copy the templates shipped in this folder's categories/ into the configured templates folder
copy_templates() {
  local templates_dir count existing
  [[ -d "$src/categories" ]] || return 0
  count="$(find "$src/categories" -mindepth 2 -type f \( -name '*.md' -o -name '*.txt' \) | wc -l)"
  (( count > 0 )) || return 0
  templates_dir="$(bash -c 'source "$1"; load_config; printf %s "$templates_dir"' _ "$src/lib/fzp/common.sh")"
  [[ -d "$templates_dir" ]] || return 0
  [[ "$(realpath "$templates_dir")" == "$(realpath "$src/categories")" ]] && return 0
  existing="$(find "$templates_dir" -mindepth 2 -type f \( -name '*.md' -o -name '*.txt' \) | wc -l)"
  local default=y
  (( existing == 0 )) || default=n
  if ask "Copy the $count templates in $(shorten_home "$src/categories") into your templates folder $(shorten_home "$templates_dir")? Existing files are kept" "$default"; then
    local f copied=0
    while IFS= read -r f; do
      [[ -e "$templates_dir/$f" ]] && continue
      mkdir -p "$templates_dir/$(dirname "$f")"
      cp "$src/categories/$f" "$templates_dir/$f"
      copied=$((copied + 1))
    done < <(cd "$src/categories" && find . -mindepth 2 -type f \( -name '*.md' -o -name '*.txt' \) -printf '%P\n')
    ok "Copied $copied templates into $(shorten_home "$templates_dir") ($((count - copied)) already there)"
  fi
}

# True when $prefix holds files of an fzp install (the ones remove_installed would remove)
is_installed() {
  [[ -L "$bin_dst" || -L "$lib_dst" || -L "$comp_dst" || -f "$lib_dst/common.sh" ]] ||
    grep -qs 'FuzzyPaste' "$bin_dst" || grep -qs '_fzp' "$comp_dst"
}

# Asks everything first, then removes fzp, and optionally the PATH line and the config file.
# The templates folder is never deleted: it's the user's own work, and may hold other files.
uninstall() {
  local info config dir count installed=0 remove_path=n remove_config=n
  # Where the config file and templates are, as fzp itself sees them
  mapfile -t info < <(bash -c 'source "$1"; load_config
    printf "%s\n" "$config_file" "$templates_dir" "$(count_templates "$templates_dir")"' _ "$src/lib/fzp/common.sh")
  config="${info[0]}" dir="${info[1]}" count="${info[2]}"

  title "FuzzyPaste · uninstall"
  if is_installed; then
    installed=1
    printf '   This removes fzp from %s. Your templates are kept.\n\n' "$(shorten_home "$prefix")"
    # Without a terminal the command itself is the confirmation
    if [[ -t 0 ]] && ! ask "Uninstall fzp?" y; then cancel Uninstall; fi
  else
    warn "fzp isn't installed in $(shorten_home "$prefix")."
  fi
  if [[ -f "$bashrc" ]] && grep -qF "$marker" "$bashrc" &&
    ask "Also remove the PATH line the installer added to ~/.bashrc?" y; then
    remove_path=y
  fi
  if [[ -f "$config" ]] && ask "Also delete your config file $(shorten_home "$config")?" n; then
    remove_config=y
  fi
  echo

  if (( installed )); then
    remove_installed
    ok "Removed fzp from $(shorten_home "$prefix")"
  fi
  if [[ "$remove_path" == y ]]; then
    cp "$bashrc" "$bashrc.fzp-backup"
    sed -i "/^$marker\$/,+1d" "$bashrc"
    ok "PATH line removed (backup: ~/.bashrc.fzp-backup)"
  fi
  if [[ "$remove_config" == y ]]; then
    rm -f "$config"
    rmdir "$(dirname "$config")" 2>/dev/null || true
    ok "Deleted $(shorten_home "$config")"
  fi
  if [[ -d "$dir" ]]; then
    local what="$count templates"
    (( count == 1 )) && what="1 template"
    printf '   Kept your templates: %s (%s)\n' "$(shorten_home "$dir")" "$what"
  fi
  [[ "$remove_config" == y || ! -f "$config" ]] || printf '   Kept your config file: %s\n' "$(shorten_home "$config")"
  echo
}

while (( $# )); do
  case "$1" in
    --copy) mode=copy ;;
    --prefix) [[ $# -ge 2 ]] || die "--prefix needs a folder"; prefix="$(realpath -m "$2")"; shift ;;
    --uninstall) mode=uninstall ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
  shift
done
(( EUID != 0 )) || die "Run the installer as your normal user, not as root: fzp is installed per user."
set_paths

if [[ "$mode" == uninstall ]]; then
  uninstall
  exit 0
fi

title "FuzzyPaste · install"
check_existing
check_requirements
echo
install_files
fix_shell
echo
setup_config
copy_templates
title "Done"
printf '   Open a new terminal, then run "fzp" (or "fzp help").\n\n'
