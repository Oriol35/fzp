# Shared by every fzp command and by the installer: where things are installed, the settings, prompts, the
# templates folder, the fzf look, full-screen handling and the preview. Sourced, not run on its own.

# Where the installer puts fzp, for this user
install_bin="$HOME/.local/bin/fzp"
install_lib="$HOME/.local/lib/fzp"
install_completion="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/fzp"
bashrc_file="$HOME/.bashrc"
# The line above the PATH line the installer adds to ~/.bashrc, so it can be found and removed again
bashrc_marker='# Added by the fzp installer'
default_templates_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fzp"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# A done step, and a warning
ok_line() { printf '\e[32m ✓\e[0m %s\n' "$*"; }
warn_line() { printf '\e[33m ⚠\e[0m %s\n' "$*"; }

# "1 template", "3 templates"
plural() { if (( $1 == 1 )); then echo "1 $2"; else echo "$1 $2s"; fi; }

# The home folder is shown as "~"
shorten_home() {
  if [[ "$1" == "$HOME" || "$1" == "$HOME/"* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}

# A folder as fzp keeps it: "~" means the home folder, a relative path starts from the home folder (not from
# wherever fzp is run), and "..", "//" and a trailing "/" are tidied up. Symlinks are kept as they are.
normalize_dir() {
  local dir="$1"
  if [[ "$dir" == "~" || "$dir" == "~/"* ]]; then
    dir="$HOME${dir:1}"
  elif [[ "$dir" != /* ]]; then
    dir="$HOME/$dir"
  fi
  realpath -ms -- "$dir"
}

# Reads the config file: "key = value" lines, read as text and never run. Sets config_file, templates_dir
# (the default when the file doesn't set it) and config_problems, the messages about lines fzp can't use.
load_config() {
  local line key value n=0 where
  config_file="${XDG_CONFIG_HOME:-$HOME/.config}/fzp/config"
  templates_dir="$default_templates_dir"
  config_problems=()
  [[ -f "$config_file" ]] || return 0
  where="$(shorten_home "$config_file")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == '#'* ]] && continue
    key="$(trim "${line%%=*}")"
    value=""
    [[ "$line" == *=* ]] && value="$(trim "${line#*=}")"
    case "$key" in
      templates_dir)
        if [[ -n "$value" ]]; then
          templates_dir="$(normalize_dir "$value")"
        else
          config_problems+=("\"templates_dir\" is empty in $where (line $n), so the default folder is used")
        fi ;;
      *) config_problems+=("ignoring unknown setting \"$key\" in $where (line $n)") ;;
    esac
  done <"$config_file"
}

# Points out config lines fzp can't use, so a typo doesn't go unnoticed
warn_config() {
  local problem
  for problem in "${config_problems[@]}"; do
    echo "fzp: $problem" >&2
  done
}

# Writes the config file (load_config sets where) with $1 as the templates folder
write_config() {
  mkdir -p "$(dirname "$config_file")"
  printf '%s\n' '# FuzzyPaste settings: one "key = value" per line, no quotes needed.' '' \
    '# Folder holding the templates; each subfolder is a category' \
    "templates_dir = $(shorten_home "$1")" >"$config_file"
}

# Yes/no question; $2 is the answer Enter gives (y or n). Returns 0 for yes, 1 for no and 2 when the user
# presses Ctrl-D. Without a terminal it returns the default answer without asking.
ask() {
  local answer hint="[Y/n]"
  [[ "$2" == n ]] && hint="[y/N]"
  if [[ ! -t 0 ]]; then
    [[ "$2" == y ]]
    return
  fi
  read -r -p " $1 $hint " answer || { echo; return 2; }
  [[ "${answer:-$2}" == [yY]* ]]
}

# Asks for the templates folder, prefilled with $1, and sets answer_dir to it (as normalize_dir keeps it).
# Fails when the user presses Ctrl-D. Without a terminal it takes $1.
ask_folder() {
  local dir=""
  if [[ ! -t 0 ]]; then
    answer_dir="$(normalize_dir "$1")"
    return 0
  fi
  while [[ -z "$dir" ]]; do
    read -r -e -i "$(shorten_home "$1")" \
      -p $'\001\e[1;36m\002 Templates folder:\001\e[0m\002 ' dir || { echo; return 1; }
    dir="$(trim "$dir")"
  done
  answer_dir="$(normalize_dir "$dir")"
}

# Number of templates in the templates folder $1
count_templates() {
  [[ -d "$1" ]] || { echo 0; return; }
  # From inside the folder, so hidden folders in its own path (~/.local) don't count as hidden
  (cd "$1" && template_files | wc -l)
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

# Each folder in the templates folder is a category, except hidden ones and "all", which is the name of the
# tab with every template
categories() {
  find . -mindepth 1 -maxdepth 1 -type d -not -name '.*' -not -name all -printf '%P\n' | sort
}

# Every template, as <category>/<file>, relative to the templates folder: the non-empty text files right inside
# a category folder, with any extension. Hidden files are skipped, and so are binary ones (grep -I, in the C
# locale so text in another encoding isn't taken for binary).
template_files() {
  find . -mindepth 2 -maxdepth 2 -type f -not -name '.*' -not -path './.*' -not -path './all/*' -print0 |
    { LC_ALL=C xargs -0 -r grep -lIZ '' -- || true; } | tr '\0' '\n' | sed 's|^\./||' | sort
}

# A template's name: its file name without the folder and the extension
template_name() {
  local name="${1##*/}"
  printf '%s' "${name%.*}"
}

# A leading "#", "##"... and the spaces after it aren't part of a description
strip_hashes() { sed 's/^#\+ *//'; }

# A template's description: its first line, without the leading "#"s or a Windows line ending
template_description() { head -n1 "$1" | sed 's/\r$//' | strip_hashes; }

# A template's body, the part fzp copies: everything after the description line and the blank lines right
# after it, byte for byte (a line holding only a Windows line ending counts as blank)
template_body() { tail -n +2 "$1" | sed $'/[^\r]/,$!d'; }

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

# fzp needs fzf 0.67 or newer. Returns 0 when the fzf at $1 accepts every option and action fzp uses
# (an older one exits with status 2); otherwise prints fzf's complaint and fails.
fzf_check() {
  local status=0 error
  error="$("$1" --filter=x --style=full --footer=x --footer-label=x --freeze-left=1 --gutter=x \
    --ghost=x --no-input --list-label=x --input-label=x --header-first --info=inline-right \
    --tabstop=1 --no-clear --layout=reverse-list --with-shell=x \
    --bind 'tab:transform-footer(echo),alt-enter:print-query,change:refresh-preview' \
    </dev/null 2>&1 >/dev/null)" || status=$?
  (( status <= 1 )) && return 0
  printf '%s\n' "${error:-$1 exited with status $status}"
  return 1
}

# The fzf look every command shares; callers add their own labels, keys and preview. fzf runs the
# callbacks with bash, whatever the user's shell is.
fzf_ui() {
  "$fzp_fzf" --with-shell 'bash -c' --ansi --style=full --layout=reverse-list --header-first \
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
  # Through the environment, as awk -v would treat backslashes in the query as escapes
  q="$1" base="$2" "$fzp_awk" '
    BEGIN {
      q = ENVIRON["q"]; base = ENVIRON["base"]
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
  template_description "$1" | word_wrap "$width" | highlight "$query" $'\e[1;36m' |
    sed $'s/.*/\e[1;36m&\e[0m/'
  echo
  template_body "$1" | word_wrap "$width" | highlight "$query" ''
}
