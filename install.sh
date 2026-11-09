#!/usr/bin/env bash
# Installs FuzzyPaste (fzp) for the current user, in ~/.local. Run it from a copy of the repository
# (./install.sh), or straight from GitHub:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/Oriol35/fzp/main/install.sh)"
# It asks every question before changing anything. Run it again to update fzp; `fzp uninstall`
# removes it. Everything below is functions and main runs on the last line, so a download cut short
# runs nothing.
set -euo pipefail

repo=Oriol35/fzp
# The fzf downloaded when this computer has none recent enough. Bumped after testing fzp with it.
fzf_version=0.74.5

usage() {
  cat <<'EOF'
Install FuzzyPaste (fzp) for your user, in ~/.local.

  install.sh                   install, or update, fzp
  install.sh --version X.Y.Z   install that release of fzp (when not run from a copy of the repository)
  install.sh --help            show this help

Remove it with: fzp uninstall
EOF
}

die() { printf '\e[31m ✗\e[0m %s\n' "$*" >&2; exit 1; }
title() { printf '\n\e[1;36m %s\e[0m\n\n' "$*"; }
cancel() { printf '\n Install cancelled. Nothing was changed.\n\n'; exit 0; }

# Checks what's needed before anything else runs: not root, bash 4.4+, and the tools fzp uses
check_basics() {
  local tool
  (( EUID != 0 )) || die "Run the installer as your normal user, not as root: fzp is installed per user."
  (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) ||
    die "fzp needs bash 4.4 or newer (this is $BASH_VERSION)."
  for tool in sed find awk tar sha256sum iconv tput realpath; do
    command -v "$tool" >/dev/null || die "fzp needs \"$tool\", which isn't installed."
  done
}

need_curl() { command -v curl >/dev/null || die "The installer needs \"curl\" to download, which isn't installed."; }

# Sets src to a folder with fzp's files: the copy of the repository this script is in, or else the
# release downloaded from GitHub into the temporary folder $work ($1: the version, or empty for the latest)
find_source() {
  local self="${BASH_SOURCE[0]:-}" dir tag url
  if [[ -n "$self" && -f "$self" ]]; then
    dir="$(cd "$(dirname "$self")" && pwd)"
    if [[ -f "$dir/bin/fzp" && -f "$dir/lib/fzp/common.sh" ]]; then
      src="$dir"
      return
    fi
  fi
  need_curl
  if [[ -n "$1" ]]; then
    tag="v${1#v}"
  else
    # github.com/<repo>/releases/latest redirects to the latest release's page, which ends in its tag
    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")" ||
      die "Couldn't reach GitHub to find the latest fzp release."
    tag="${url##*/}"
    [[ "$tag" == v[0-9]* ]] || die "Couldn't find an fzp release on GitHub."
  fi
  echo " Downloading fzp $tag…"
  curl -fsSL "https://github.com/$repo/archive/refs/tags/$tag.tar.gz" | tar xz -C "$work" ||
    die "Couldn't download fzp $tag."
  src="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'fzp-*' | head -n1)"
  [[ -f "$src/bin/fzp" ]] || die "The fzp $tag download doesn't look like fzp."
}

# The fzf release name for this computer's processor, or fails
fzf_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) return 1 ;;
  esac
}

# Downloads fzf $fzf_version for processor $1 into $work/fzf, checked against the release's checksums
download_fzf() {
  local base="https://github.com/junegunn/fzf/releases/download/v$fzf_version" file="fzf-$fzf_version-linux_$1.tar.gz"
  need_curl
  mkdir -p "$work/fzf-download"
  (
    cd "$work/fzf-download"
    curl -fsSLO "$base/$file" && curl -fsSLO "$base/fzf_${fzf_version}_checksums.txt" &&
      grep -F "  $file" "fzf_${fzf_version}_checksums.txt" | sha256sum -c --status &&
      tar xzf "$file" fzf
  ) || die "Couldn't download fzf $fzf_version, or it didn't match its checksum. Nothing was changed."
  mv "$work/fzf-download/fzf" "$work/fzf"
  ok_line "Downloaded fzf $fzf_version (checksum verified)"
}

# Version of the fzp in folder $1
source_version() { sed -n 's/^FZP_VERSION="\(.*\)"$/\1/p' "$1/bin/fzp"; }

# An fzp already installed here: offer to update it. Something else called fzp there: stop.
check_existing() {
  local old other status=0
  if [[ -e "$install_bin" || -L "$install_bin" ]]; then
    [[ -L "$install_bin" ]] || grep -qs FuzzyPaste "$install_bin" ||
      die "$(shorten_home "$install_bin") already exists and isn't fzp, so the installer leaves it alone."
    old="$("$install_bin" --version 2>/dev/null | awk '{ print $2 }')"
    ask "Update fzp ${old:-(unknown version)} to $(source_version "$src")?" y || status=$?
    (( status == 0 )) || cancel
  fi
  other="$(type -P fzp || true)"
  if [[ -n "$other" && "$other" != "$install_bin" ]]; then
    warn_line "There's another fzp at $(shorten_home "$other"), which comes first on your PATH."
  fi
}

# Decides where fzp's fzf comes from, in fzf_plan: keep (the one a previous install downloaded),
# system, download, or none (fzp won't run until a recent fzf is installed)
plan_fzf() {
  local error arch status=0
  if [[ -x "$install_lib/fzf" ]] && fzf_check "$install_lib/fzf" >/dev/null; then
    fzf_plan=keep
    ok_line "fzf $("$install_lib/fzf" --version | cut -d' ' -f1) (downloaded for fzp)"
    return
  fi
  if command -v fzf >/dev/null; then
    if error="$(fzf_check fzf)"; then
      fzf_plan=system
      ok_line "fzf $(fzf --version | cut -d' ' -f1)"
      return
    fi
    warn_line "Your fzf $(fzf --version | cut -d' ' -f1) is too old for fzp, which needs 0.67 or newer ($error)."
  else
    warn_line "fzf isn't installed. fzp needs fzf 0.67 or newer."
  fi
  fzf_plan=none
  if ! arch="$(fzf_arch)"; then
    warn_line "There's no fzf download for this processor ($(uname -m)). Install fzf 0.67 or newer from https://github.com/junegunn/fzf, then run fzp."
    return
  fi
  ask "Download fzf $fzf_version for fzp? It goes into ~/.local/lib/fzp, not on your PATH, so it doesn't replace yours." y ||
    status=$?
  (( status != 2 )) || cancel
  if (( status == 0 )); then
    fzf_plan=download
  else
    warn_line "fzp won't run until fzf 0.67 or newer is installed."
  fi
}

check_extras() {
  local tool
  if "$fzp_awk" --version 2>/dev/null | grep -q 'GNU Awk'; then
    ok_line "GNU awk"
  else
    warn_line "GNU awk isn't installed: search highlights in the preview become case-sensitive, and accented letters can be cut. Install \"gawk\" to fix it."
  fi
  if tool="$(clipboard_tool)"; then
    ok_line "Clipboard: $tool"
  else
    warn_line "No clipboard tool found: install wl-clipboard (Wayland), xclip or xsel (X11), or fzp can't copy."
  fi
  if [[ -f /usr/share/bash-completion/bash_completion || -f /etc/bash_completion ]]; then
    ok_line "bash-completion"
  else
    warn_line "The bash-completion package isn't installed, so Tab won't complete fzp's commands."
  fi
}

# Only on a first install (no config file yet): where the templates go, and whether to copy the examples
plan_templates() {
  local examples existing status=0
  new_config=n copy_examples=n
  [[ -f "$config_file" ]] && return
  new_config=y
  printf '\n Where should your templates live? Press Enter for the default, or type another folder.\n'
  ask_folder "$templates_dir" || cancel
  templates_dir="$answer_dir"
  [[ -d "$src/examples" ]] || return 0
  examples="$(find "$src/examples" -mindepth 2 -maxdepth 2 -type f | wc -l)"
  (( examples > 0 )) || return 0
  existing="$(count_templates "$templates_dir")"
  ask "Copy the $examples example templates into it? Files already there are kept." \
    "$( (( existing == 0 )) && echo y || echo n)" || status=$?
  (( status != 2 )) || cancel
  (( status == 0 )) && copy_examples=y
  return 0
}

# Whether to add ~/.local/bin to PATH in ~/.bashrc
plan_path() {
  local status=0
  add_path=n
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) return ;;
  esac
  if grep -qsF "$bashrc_marker" "$bashrc_file"; then
    ok_line "~/.bashrc already adds ~/.local/bin to PATH (active in new terminals)"
    return
  fi
  ask "~/.local/bin isn't on your PATH. Add it in ~/.bashrc?" y || status=$?
  (( status != 2 )) || cancel
  (( status == 0 )) && add_path=y
  return 0
}

install_files() {
  local f
  # A previous install's code goes, its downloaded fzf stays when it's still the one to use
  if [[ -L "$install_lib" ]]; then
    rm -f "$install_lib"
  elif [[ -d "$install_lib" ]]; then
    find "$install_lib" -mindepth 1 -maxdepth 1 ! -name fzf -exec rm -rf {} +
    [[ "$fzf_plan" == keep ]] || rm -f "$install_lib/fzf"
  fi
  rm -f "$install_bin" "$install_completion"
  mkdir -p "$(dirname "$install_bin")" "$install_lib" "$(dirname "$install_completion")"
  install -m 755 "$src/bin/fzp" "$install_bin"
  install -m 644 "$src"/lib/fzp/*.sh "$install_lib/"
  install -m 644 "$src/share/bash-completion/completions/fzp" "$install_completion"
  [[ "$fzf_plan" == download ]] && install -m 755 "$work/fzf" "$install_lib/fzf"
  ok_line "Installed fzp $(source_version "$src") in $(shorten_home "$install_bin")"
}

setup_templates() {
  local f copied=0 kept=0
  [[ "$new_config" == y ]] || return 0
  write_config "$templates_dir"
  ok_line "Config file: $(shorten_home "$config_file")"
  mkdir -p "$templates_dir"
  if [[ "$copy_examples" == y ]]; then
    while IFS= read -r f; do
      if [[ -e "$templates_dir/$f" ]]; then
        kept=$((kept + 1))
      else
        mkdir -p "$templates_dir/${f%/*}"
        cp -- "$src/examples/$f" "$templates_dir/$f"
        copied=$((copied + 1))
      fi
    done < <(cd "$src/examples" && find . -mindepth 2 -maxdepth 2 -type f -printf '%P\n' | sort)
    ok_line "Copied $(plural "$copied" example) into $(shorten_home "$templates_dir")$( (( kept )) && echo " ($kept already there)")"
  else
    ok_line "Templates folder: $(shorten_home "$templates_dir")"
  fi
}

add_to_path() {
  [[ "$add_path" == y ]] || return 0
  if [[ -f "$bashrc_file" ]]; then
    cp -- "$bashrc_file" "$bashrc_file.fzp-backup"
    # A last line without a newline would otherwise run into the marker
    [[ -s "$bashrc_file" && -n "$(tail -c1 "$bashrc_file")" ]] && echo >>"$bashrc_file"
  fi
  printf '%s\n%s\n' "$bashrc_marker" 'export PATH="$HOME/.local/bin:$PATH"' >>"$bashrc_file"
  ok_line "Added ~/.local/bin to PATH in ~/.bashrc$([[ -f "$bashrc_file.fzp-backup" ]] && echo " (backup: ~/.bashrc.fzp-backup)")"
}

main() {
  local version=""
  while (( $# )); do
    case "$1" in
      --version) [[ $# -ge 2 ]] || die "--version needs a version, like 0.1.0"; version="$2"; shift ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; exit 1 ;;
    esac
    shift
  done
  check_basics
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT

  title "FuzzyPaste · install"
  find_source "$version"
  source "$src/lib/fzp/common.sh"
  source "$src/lib/fzp/clipboard.sh"
  load_config

  # Every question first
  check_existing
  plan_fzf
  check_extras
  plan_templates
  plan_path
  echo

  [[ "$fzf_plan" == download ]] && download_fzf "$(fzf_arch)"
  install_files
  setup_templates
  add_to_path

  title "Done"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) printf '   Run "fzp" to pick a template, or "fzp help" to see where everything is.\n\n' ;;
    *) printf '   Open a new terminal, then run "fzp" (or "fzp help" to see where everything is).\n\n' ;;
  esac
}

main "$@"
