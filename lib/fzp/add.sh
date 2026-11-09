# `fzp add`: save a new template into a category. Steps: text → description → category → file
# name, with a checklist of steps on top. Line 1 of the saved file is the description.

# Accented letters become plain ones (Traducció → traduccio); anything else not a-z/0-9 becomes "-"
slugify() {
  iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' |
    sed -E 's/\.(md|txt)$//; s/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# Both leave the full screen first, so the message stays visible in the terminal
cancel() { leave_screen; echo "Nothing saved."; exit 0; }
fail() { leave_screen; echo "$1 Nothing saved." >&2; exit 1; }

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

# Prints the highlighted line, or the typed text when nothing matches. Fails on Esc.
choose() {
  local out
  out="$(ui "$@")" || [[ $? -eq 1 ]] || return 1
  if [[ "$out" == *$'\n'* ]]; then printf '%s\n' "${out#*$'\n'}"; else printf '%s\n' "$out"; fi
}

# Prints the typed text. The listed lines are dimmed and only there for reference. Fails on Esc.
input() {
  local out
  out="$(sed $'s/^/\e[2m/' | ui "$@" --disabled --pointer=' ' --color='bg+:-1' \
    --bind 'up:ignore,down:ignore,ctrl-j:ignore,ctrl-k:ignore,ctrl-n:ignore,ctrl-p:ignore')" ||
    [[ $? -eq 1 ]] || return 1
  printf '%s\n' "${out%%$'\n'*}"
}

# Key hints ($1), with the current warning above them when a typed name couldn't be used.
# Runs in a subshell, so callers clear $warning once the menu has shown it.
warning=""
hints() {
  [[ -n "$warning" ]] && printf '\e[33m⚠ %s\e[0m\n' "$warning"
  printf '%s' "$1"
}

add_main() {
  enter_templates_dir
  preview="$(mktemp --suffix=.md)"
  tmp=""
  trap 'rm -f "$preview" "$tmp"; leave_screen' EXIT
  trap 'echo; cancel' INT
  enter_screen

  # 1. Text
  source="$(printf '%s\n' clipboard editor 'type or paste here' |
    choose --no-input --list-label=' Where is the text? ' --preview-window=hidden \
      --header='↵ choose  ·  esc cancel')" || cancel
  case "$source" in
    clipboard)
      content="$(paste_from_clipboard)" || fail "The clipboard is empty or doesn't hold text." ;;
    editor)
      tmp="$(mktemp --suffix=.md)"
      # The editor gets the normal screen; unquoted on purpose, so VISUAL="code --wait" works
      leave_screen
      ${VISUAL:-${EDITOR:-nano}} "$tmp" || fail "The editor (${VISUAL:-${EDITOR:-nano}}) exited with an error."
      enter_screen
      content="$(cat "$tmp")" ;;
    "type or paste here")
      banner
      printf '\e[2m Type or paste the text, then press ctrl-d on an empty line\e[0m\n\n'
      content="$(cat)" ;;
    *) cancel ;;
  esac

  # Drop leading blank lines
  content="$(sed '/./,$!d' <<<"$content")"
  [[ -n "$content" ]] || fail "The text is empty."
  printf '%s\n' "$content" >"$preview"
  lines="$(wc -l <<<"$content")"
  values[0]="$source ($lines line$( (( lines == 1 )) || echo s))"
  current=1

  # 2. Description (first line of the file). A "# " first line is offered as the default.
  first_line="$(head -n1 <<<"$content")"
  prefill=""
  body="$content"
  if [[ "$first_line" == "# "* ]]; then
    prefill="$(strip_hashes <<<"$first_line")"
    body="$(tail -n +2 <<<"$content" | sed '/./,$!d')"
  fi
  [[ -n "$body" ]] || fail "The text is only a \"# \" title line, with nothing below it to copy."
  # A plain terminal prompt, so long descriptions wrap over several lines
  banner
  printf '\e[2m The text starts with:\e[0m\n'
  head -n8 <<<"$body" | awk -v w="$(( $(tput cols) - 8 ))" '{ if (length($0) > w) $0 = substr($0, 1, w - 1) "…"; print }' |
    sed $'s/^/\e[2m   │ \e[0m/'
  (( $(wc -l <<<"$body") > 8 )) && printf '\e[2m   │ …\e[0m\n'
  printf '\n\e[2m What does this template do? e.g. "Jira bugfix: diagnose, explain in the ticket, weigh fixes"\n'
  printf ' ↵ confirm  ·  ctrl-c cancel, nothing is saved\e[0m\n\n'
  desc=""
  while [[ -z "$desc" ]]; do
    read -r -e -i "$prefill" -p $'\001\e[1;36m\002 Description:\001\e[0m\002 ' desc || { echo; cancel; }
    desc="$(strip_hashes <<<"$desc")"
  done
  printf '# %s\n\n%s\n' "$desc" "$body" >"$preview"
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
      --header="$(hints '↵ choose  ·  alt-↵ use exactly what I typed  ·  esc cancel')")" || cancel
    warning=""
    typed="$category"
    category="$(slugify <<<"$category")"
    if [[ -z "$category" && -n "$typed" ]]; then
      warning="\"$typed\" has no usable letters (a-z, 0-9)"; continue
    elif [[ "$category" == all ]]; then
      warning="\"all\" is reserved for fzp's all tab"; category=""; continue
    fi
    [[ -z "$category" || -d "$category" ]] && continue
    create="Create $category/ and continue"
    answer="$(printf '%s\n' "$create" 'Go back to categories' |
      choose --no-input --list-label=" $category/ is a new category " \
        --header='↵ choose  ·  esc go back')" || answer=""
    [[ "$answer" == "$create" ]] || category=""
  done
  values[2]="$category/"
  current=3

  # 4. File name
  while :; do
    existing=""
    [[ -d "$category" ]] && existing="$(find "$category" -maxdepth 1 -name '*.md' -printf '%f\n' | sed 's/\.md$//' | sort)"
    if [[ -n "$existing" ]]; then list_label=" already in $category/ "; else list_label=" $category/ is new and empty "; fi
    typed="$(printf '%s' "$existing" | input --list-label="$list_label" --input-label=' File name ' \
      --ghost='lowercase-with-hyphens (.md is added)' \
      --header="$(hints '↵ confirm  ·  esc cancel, nothing is saved')")" || cancel
    warning=""
    name="$(slugify <<<"$typed")"
    if [[ -z "$name" ]]; then
      [[ -n "$typed" ]] && warning="\"$typed\" has no usable letters (a-z, 0-9)"
      continue
    fi
    path="$category/$name.md"
    [[ -e "$path" ]] || break
    answer="$(printf '%s\n' 'choose another name' "overwrite $path" |
      choose --no-input --list-label=" $path already exists " \
        --header='↵ choose  ·  esc cancel, nothing is saved')" || cancel
    [[ "$answer" == overwrite* ]] && break
  done
  values[3]="$name.md"
  current=${#STEPS[@]}

  mkdir -p "$category"
  cp "$preview" "$path"
  leave_screen
  printf '\n\e[1;36m FuzzyPaste · template saved\e[0m\n'
  steps
  printf '\n Saved to %s. It now shows up in fzp.\n' "$path"
}
