# `fzp add`: save a new template into a category. Steps: text → description → category → file
# name, with a checklist of steps on top. Line 1 of the saved file is the description; the text is
# saved exactly as given, apart from blank lines at its start.

# Accented letters become plain ones (Traducció → traduccio); anything else not a-z/0-9 becomes "-".
# Never fails: letters iconv can't read are dropped.
slugify() {
  { LC_ALL=C.UTF-8 iconv -c -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || true; } | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# The category folder for what was chosen or typed ($1): an existing category as it is, a new one
# as lowercase-with-hyphens (empty when nothing usable is left). Run in the templates folder.
resolve_category() {
  if [[ -n "$1" ]] && categories | grep -Fxq -- "$1"; then
    printf '%s' "$1"
  else
    slugify <<<"$1"
  fi
}

# Splits a typed file name ($1) into split_name, lowercase-with-hyphens (empty when nothing usable
# is left), and split_ext, lowercase, "md" when none was typed
split_file_name() {
  local base="$1" ext=""
  if [[ "$1" == *.* ]]; then
    base="${1%.*}"
    ext="$(tr '[:upper:]' '[:lower:]' <<<"${1##*.}" | tr -cd 'a-z0-9')"
  fi
  split_name="$(slugify <<<"$base")"
  split_ext="${ext:-md}"
}

# Prints the file in category $1 whose template name is $2, whatever its extension, and fails when
# there is none
name_taken() {
  local f
  for f in "$1"/*; do
    [[ -f "$f" && "$(template_name "$f")" == "$2" ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

# Both leave the full screen first, so the message stays visible in the terminal
add_cancel() { leave_screen; echo "Nothing saved."; exit 0; }
add_fail() { leave_screen; echo "$1 Nothing saved." >&2; exit 1; }

STEPS=(Text Description Category "File name")
values=()
current=0

# Checklist of steps: done ones ticked with their value, the current one highlighted
steps() {
  local i v
  for i in "${!STEPS[@]}"; do
    if (( i < current )); then
      v="${values[i]}"; (( ${#v} > 60 )) && v="${v:0:59}…"
      printf '\e[32m ✓ %-12s\e[0m \e[2m%s\e[0m\n' "${STEPS[i]}" "$v"
    elif (( i == current )); then
      printf '\e[1;36m ▸ %s\e[0m\n' "${STEPS[i]}"
    else
      printf '\e[2m ○ %s\e[0m\n' "${STEPS[i]}"
    fi
  done
}

# Title and checklist for the steps that run in the plain terminal
banner() {
  (( in_screen )) && clear
  printf '\n\e[1;36m FuzzyPaste · new template\e[0m\n'
  steps
  echo
}

# The shared fzf look with the steps on top; the preview shows the template as it will be saved
ui() {
  local stay=()
  # Inside fzp add's own full screen, fzf must not switch back to the normal screen when it exits
  (( in_screen )) && stay=(--no-clear)
  fzf_ui "${stay[@]}" --info=hidden --footer="$(steps)" --footer-label=' FuzzyPaste · new template ' \
    --preview="$FZP_SELF _preview $(printf '%q' "$preview")" --preview-label=' preview ' \
    --print-query "$@"
}

# Runs fzf ($@) and keeps its output in $out. Returns 1 on Esc and 2 when fzf fails; nothing
# matching is fine.
run_ui() {
  local status=0
  out="$("$@")" || status=$?
  case "$status" in
    0 | 1) return 0 ;;
    130) return 1 ;;
    *) return 2 ;;
  esac
}

# Ends fzp add after a menu returned $1: 1 is Esc, 2 an fzf error
add_stopped() {
  (( $1 == 1 )) && add_cancel
  add_fail "fzf failed."
}

# Prints the highlighted line, or the typed text when nothing matches. Fails like run_ui.
choose() {
  local out
  run_ui ui "$@" || return
  if [[ "$out" == *$'\n'* ]]; then printf '%s\n' "${out#*$'\n'}"; else printf '%s\n' "$out"; fi
}

# Prints the typed text. The listed lines are dimmed and only there for reference. Fails like run_ui.
input() {
  local out list
  list="$(sed $'s/^/\e[2m/')"
  run_ui ui "$@" --disabled --pointer=' ' --color='bg+:-1' \
    --bind 'up:ignore,down:ignore,ctrl-j:ignore,ctrl-k:ignore,ctrl-n:ignore,ctrl-p:ignore' <<<"$list" || return
  printf '%s\n' "${out%%$'\n'*}"
}

# Key hints ($1), with the current warning above them when a typed name couldn't be used.
# Runs in a subshell, so callers clear $warning once the menu has shown it.
warning=""
hints() {
  [[ -n "$warning" ]] && printf '\e[33m⚠ %s\e[0m\n' "$warning"
  printf '%s' "$1"
}

# Drops the blank lines at the start of file $1 (a line holding only a Windows line ending counts as blank)
drop_leading_blank_lines() { sed -i $'/[^\r]/,$!d' "$1"; }

add_main() {
  local text_source editor lines first_line prefill desc category typed create answer existing list_label
  local name ext path replace
  enter_templates_dir
  preview="$(mktemp --suffix=.md)"
  text="$(mktemp --suffix=.md)"
  body="$(mktemp)"
  trap 'rm -f "$preview" "$text" "$body"; leave_screen' EXIT
  trap 'echo; add_cancel' INT
  enter_screen

  # 1. Text. Written straight to a file, so it's kept exactly, trailing blank lines included.
  text_source="$(printf '%s\n' clipboard editor 'type or paste here' |
    choose --no-input --list-label=' Where is the text? ' --preview-window=hidden \
      --header='↵ choose  ·  esc cancel')" || add_stopped $?
  case "$text_source" in
    clipboard)
      paste_from_clipboard >"$text" || add_fail "The clipboard can't be read."
      drop_leading_blank_lines "$text"
      [[ -s "$text" ]] || add_fail "The clipboard is empty or doesn't hold text." ;;
    editor)
      editor="${VISUAL:-${EDITOR:-nano}}"
      command -v "${editor%% *}" >/dev/null || add_fail "The editor \"$editor\" wasn't found. Set VISUAL or EDITOR."
      # The editor gets the normal screen; unquoted on purpose, so VISUAL="code --wait" works
      leave_screen
      $editor "$text" || add_fail "The editor ($editor) exited with an error."
      enter_screen ;;
    "type or paste here")
      banner
      printf '\e[2m Type or paste the text, then press ctrl-d on an empty line\e[0m\n\n'
      cat >"$text" ;;
    *) add_cancel ;;
  esac
  iconv -f UTF-8 -t UTF-8 "$text" >/dev/null 2>&1 || add_fail "The text isn't valid UTF-8."
  drop_leading_blank_lines "$text"
  [[ -s "$text" ]] || add_fail "The text is empty."
  cp "$text" "$preview"
  lines="$(grep -c '' "$text")"
  values[0]="$text_source ($lines line$( (( lines == 1 )) || echo s))"
  current=1

  # 2. Description (first line of the file). A "# " first line is offered as the default.
  first_line="$(head -n1 "$text")"
  prefill=""
  cp "$text" "$body"
  if [[ "$first_line" == "# "* ]]; then
    prefill="$(strip_hashes <<<"${first_line%$'\r'}")"
    tail -n +2 "$text" >"$body"
    drop_leading_blank_lines "$body"
  fi
  [[ -s "$body" ]] || add_fail "The text is only a \"# \" title line, with nothing below it to copy."
  # A plain terminal prompt, so long descriptions wrap over several lines
  banner
  printf '\e[2m The text starts with:\e[0m\n'
  head -n8 "$body" | "$fzp_awk" -v w="$(( $(tput cols) - 8 ))" '{ if (length($0) > w) $0 = substr($0, 1, w - 1) "…"; print }' |
    sed $'s/^/\e[2m   │ \e[0m/'
  (( $(grep -c '' "$body") > 8 )) && printf '\e[2m   │ …\e[0m\n'
  printf '\n\e[2m What does this template do? e.g. "Review code for bugs, readability and edge cases"\n'
  printf ' ↵ confirm  ·  ctrl-c cancel, nothing is saved\e[0m\n\n'
  desc=""
  while [[ -z "$desc" ]]; do
    read -r -e -i "$prefill" -p $'\001\e[1;36m\002 Description:\001\e[0m\002 ' desc || { echo; add_cancel; }
    desc="$(strip_hashes <<<"$desc")"
  done
  { printf '# %s\n\n' "$desc"; cat "$body"; } >"$preview"
  values[1]="$desc"
  current=2

  # 3. Category. Enter takes the highlighted category; alt-enter takes exactly what was typed, so
  # a new name that fuzzy-matches an existing one (cat vs cat1) can still be created. A new name
  # must be confirmed first, and going back keeps what was typed. The folder is created on save.
  category=""
  typed=""
  while [[ -z "$category" ]]; do
    category="$(categories | choose --list-label=' Category ' --query="$typed" \
      --input-label=' type to filter, or type a new name ' --bind 'alt-enter:print-query' \
      --header="$(hints '↵ choose  ·  alt-↵ use exactly what I typed  ·  esc cancel')")" || add_stopped $?
    warning=""
    typed="$category"
    category="$(resolve_category "$category")"
    if [[ -z "$category" && -n "$typed" ]]; then
      warning="\"$typed\" has no usable letters (a-z, 0-9)"; continue
    elif [[ "$category" == all ]]; then
      warning="\"all\" is reserved for fzp's all tab"; category=""; continue
    fi
    [[ -z "$category" ]] && continue
    categories | grep -Fxq -- "$category" && break
    create="Create $category/ and continue"
    answer="$(printf '%s\n' "$create" 'Go back to categories' |
      choose --no-input --list-label=" $category/ is a new category " \
        --header='↵ choose  ·  esc go back')" || answer=""
    [[ "$answer" == "$create" ]] || category=""
  done
  values[2]="$category/"
  current=3

  # 4. File name. Any plain-text extension works; .md when none is typed. A name already used in the
  # category, with any extension, has to be replaced or changed.
  while :; do
    existing=""
    [[ -d "$category" ]] && existing="$(find "$category" -maxdepth 1 -type f -not -name '.*' -printf '%f\n' | sort)"
    if [[ -n "$existing" ]]; then list_label=" already in $category/ "; else list_label=" $category/ is new and empty "; fi
    typed="$(printf '%s' "$existing" | input --list-label="$list_label" --input-label=' File name ' \
      --ghost='name, or name.ext' \
      --header="$(hints $'Any plain-text extension works: .md, .txt, .sh, .sql… (.md if you type none)\n↵ confirm  ·  esc cancel, nothing is saved')")" || add_stopped $?
    warning=""
    split_file_name "$typed"
    name="$split_name" ext="$split_ext"
    if [[ -z "$name" ]]; then
      [[ -n "$typed" ]] && warning="\"$typed\" has no usable letters (a-z, 0-9)"
      continue
    fi
    path="$category/$name.$ext"
    replace=""
    existing="$(name_taken "$category" "$name")" || break
    answer="$(printf '%s\n' 'choose another name' "replace $existing" |
      choose --no-input --list-label=" $existing already exists " \
        --header='↵ choose  ·  esc cancel, nothing is saved')" || add_stopped $?
    [[ "$answer" == replace* ]] && { replace="$existing"; break; }
  done
  values[3]="$name.$ext"
  current=${#STEPS[@]}

  mkdir -p "$category"
  [[ -n "$replace" ]] && rm -f -- "$replace"
  cp "$preview" "$path"
  leave_screen
  printf '\n\e[1;36m FuzzyPaste · template saved\e[0m\n'
  steps
  printf '\n Saved to %s. It now shows up in fzp.\n' "$(shorten_home "$templates_dir/$path")"
}
