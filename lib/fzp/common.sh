# Shared by `fzp` and `fzp add`: settings, the templates folder, the clipboard, the fzf look,
# full-screen handling and the preview. Sourced by bin/fzp, not run on its own.

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# "~" at the start of a path means the home folder, and is shown that way
expand_home() {
  if [[ "$1" == "~" || "$1" == "~/"* ]]; then printf '%s' "$HOME${1:1}"; else printf '%s' "$1"; fi
}
shorten_home() {
  if [[ "$1" == "$HOME" || "$1" == "$HOME/"* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}

# Settings: built-in defaults, then the config file ("key = value" lines, read as text and never
# run), then the FZP_TEMPLATES_DIR environment variable. Settings from older fzp versions still
# work; they're listed in old_settings so fzp can suggest updating the file.
load_config() {
  local key value old_dir=""
  config_file="${FZP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/fzp/config}"
  templates_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fzp"
  old_settings=()
  unknown_settings=()
  if [[ -f "$config_file" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      key="$(trim "$key")"
      value="$(trim "${value:-}")"
      case "$key" in
        '' | '#'*) ;;
        templates_dir) templates_dir="$value" ;;
        # Old name of templates_dir
        library) old_dir="$value"; old_settings+=("$key") ;;
        # Removed: fzp is always full screen
        height) old_settings+=("$key") ;;
        *) unknown_settings+=("$key") ;;
      esac
    done <"$config_file"
    # templates_dir wins when the file has both names
    grep -qE '^[[:space:]]*templates_dir[[:space:]]*=' "$config_file" || templates_dir="${old_dir:-$templates_dir}"
  fi
  # What the config file says (or the default), before the environment variable
  templates_dir_setting="$(expand_home "$templates_dir")"
  templates_dir="$(expand_home "${FZP_TEMPLATES_DIR:-$templates_dir}")"
}

# Points out settings fzp doesn't use, so a typo or an outdated config file doesn't go unnoticed
warn_config() {
  local key
  if (( ${#old_settings[@]} )); then
    echo "fzp: your config file $(shorten_home "$config_file") is from an older fzp. Run \"fzp config\" to update it." >&2
  fi
  for key in "${unknown_settings[@]}"; do
    echo "fzp: ignoring unknown setting \"$key\" in $(shorten_home "$config_file")" >&2
  done
}

# Number of templates in the templates folder $1
count_templates() {
  [[ -d "$1" ]] || { echo 0; return; }
  # From inside the folder, so hidden folders in its own path (~/.local) don't count as hidden
  (cd "$1" && find . -mindepth 2 -type f -not -path '*/.*' \( -name '*.md' -o -name '*.txt' \) | wc -l)
}

# Moves into the templates folder, or explains how to point fzp at one
enter_templates_dir() {
  if [[ ! -d "$templates_dir" ]]; then
    if [[ -f "$config_file" ]]; then
      echo "fzp: the templates folder $templates_dir doesn't exist. Create it, or change \"templates_dir\" in $config_file (\"fzp config\" shows where it is)." >&2
    else
      echo "fzp: the templates folder $templates_dir doesn't exist, and there is no config file yet. Run \"fzp config\" to create one." >&2
    fi
    exit 1
  fi
  cd "$templates_dir"
}

# Each subfolder of the templates folder is a category
categories() {
  find . -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '%P\n' | sort
}

# Every template, as <category>/<name>.md (or .txt), relative to the templates folder
template_files() {
  find . -mindepth 2 -type f -not -path '*/.*' \( -name '*.md' -o -name '*.txt' \) -printf '%P\n' | sort
}

# A leading "#", "##"... and the spaces after it aren't part of a description
strip_hashes() { sed 's/^#\+ *//'; }

copy_to_clipboard() {
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null; then
    wl-copy
  elif command -v xclip >/dev/null; then
    xclip -selection clipboard
  elif command -v xsel >/dev/null; then
    xsel --clipboard --input
  else
    echo "No clipboard tool found (install wl-clipboard or xclip)." >&2
    return 1
  fi
}

# Fails when the clipboard is empty or doesn't hold text
paste_from_clipboard() {
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-paste >/dev/null; then
    wl-paste --no-newline 2>/dev/null
  elif command -v xclip >/dev/null; then
    xclip -selection clipboard -o 2>/dev/null
  elif command -v xsel >/dev/null; then
    xsel --clipboard --output 2>/dev/null
  else
    echo "No clipboard tool found (install wl-clipboard or xclip)." >&2
    return 1
  fi
}

# For fzp add, which mixes fzf screens with plain terminal prompts: take over the whole terminal
# like vim does for all its steps, and give the previous contents back on exit. (fzf does this by
# itself for the picker; --height=100% would too, but switches back after each step.)
# Anything printed for the user afterwards must come after leave_screen.
in_screen=0
enter_screen() {
  [[ -t 1 ]] || return 0
  tput smcup
  clear
  in_screen=1
}
leave_screen() {
  (( in_screen )) || return 0
  tput rmcup
  in_screen=0
}

# The fzf look both commands share; callers add their own labels, keys and preview
fzf_ui() {
  fzf --ansi --style=full --layout=reverse-list --header-first \
    --pointer='▌' --gutter=' ' --prompt='› ' --preview-window='right,55%,noinfo' \
    --color='label:bold:cyan,pointer:cyan,hl:magenta:underline,hl+:bold:magenta:underline,ghost:dim' \
    "$@"
}

# The preview needs GNU awk (case-insensitive matching, accented letters counted as one); some
# systems install it as gawk next to a different default awk
fzp_awk="$(command -v gawk || echo awk)"

# Wraps lines at spaces to fit $1 columns, keeping each line's indentation
word_wrap() {
  "$fzp_awk" -v w="$1" '
    length($0) <= w { print; next }
    {
      match($0, /^[ \t]*/); indent = substr($0, 1, RLENGTH); line = indent
      n = split(substr($0, RLENGTH + 1), words, " ")
      room = w - length(indent); if (room < 10) room = 10
      for (i = 1; i <= n; i++) {
        if (line != indent && length(line) + 1 + length(words[i]) > w) { print line; line = indent }
        while (length(words[i]) > room) { print indent substr(words[i], 1, room); words[i] = substr(words[i], room + 1) }
        line = line (line == indent ? "" : " ") words[i]
      }
      print line
    }'
}

# Marks every case-insensitive occurrence of the fzf query's words ($1) in bold underlined magenta,
# then switches back to the line's own style ($2). Negated (!word) and | terms are skipped.
highlight() {
  "$fzp_awk" -v q="$1" -v base="$2" '
    BEGIN {
      IGNORECASE = 1
      n = split(q, terms, " ")
      for (i = 1; i <= n; i++) {
        t = terms[i]
        if (t ~ /^!/ || t == "|") continue
        sub(/^\x27/, "", t); sub(/^\^/, "", t); sub(/\$$/, "", t)
        if (t == "") continue
        gsub(/[][\\.^$*+?(){}|\/]/, "\\\\&", t)
        re = re (re == "" ? "" : "|") t
      }
    }
    re == "" { print; next }
    {
      s = $0; out = ""
      while (match(s, re)) {
        out = out substr(s, 1, RSTART - 1) "\033[1;4;35m" substr(s, RSTART, RLENGTH) "\033[0m" base
        s = substr(s, RSTART + RLENGTH)
      }
      print out s
    }'
}

# A blank top margin, the description in bold cyan, then the body, all wrapped to the preview
# width, with the search query ($2, optional) highlighted
render_preview() {
  local width=$(( ${FZF_PREVIEW_COLUMNS:-80} - 1 )) query="${2:-}"
  echo
  head -n1 "$1" | strip_hashes | word_wrap "$width" | highlight "$query" $'\e[1;36m' |
    sed $'s/.*/\e[1;36m&\e[0m/'
  echo
  tail -n +2 "$1" | sed '/./,$!d' | word_wrap "$width" | highlight "$query" ''
}
