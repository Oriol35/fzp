# `fzp`: pick a template and copy its body (everything after the description line) to the
# clipboard. Tab / Shift-Tab switch category tabs. fzf runs the tab callbacks as separate
# processes, so the active tab is kept in the file $FZP_TAB.

# Category tabs, with the active one highlighted
tabs() {
  local active c line=""
  active="$(<"$FZP_TAB")"
  for c in all $(categories); do
    if [[ "$c" == "$active" ]]; then
      line+=$'\e[1;30;46m '"$c"$' \e[0m  '
    else
      line+=$'\e[2m '"$c"$' \e[0m  '
    fi
  done
  printf '%s\n' "$line"
}

# One row per template in the active tab: <path> TAB <category> TAB <name> TAB <description>.
# Category and name stay frozen while the description scrolls to the match. Names are padded
# with U+2800 (braille blank) because fzf trims trailing spaces in frozen fields.
list() {
  local active f files=() name width=0 pad category
  active="$(<"$FZP_TAB")"
  while IFS= read -r f; do
    [[ "$active" == all || "$f" == "$active/"* ]] || continue
    files+=("$f")
    name="$(basename "${f%.*}")"
    (( ${#name} > width )) && width=${#name}
  done < <(template_files)
  for f in "${files[@]}"; do
    name="$(basename "${f%.*}")"
    printf -v pad '%*s' $(( width + 2 - ${#name} )) ''
    pad="${pad// /$'\xe2\xa0\x80'}"
    category=""
    [[ "$active" == all ]] && printf -v category '\e[36m%-10s\e[0m' "${f%%/*}"
    printf '%s\t%s\t%s%s\t\e[2m%s\e[0m\n' "$f" "$category" "$name" "$pad" "$(head -n1 "$f" | strip_hashes)"
  done
}

# Move the active tab by $1 steps (1 = next, -1 = previous)
cycle() {
  local cats active i
  mapfile -t cats < <(echo all; categories)
  active="$(<"$FZP_TAB")"
  for i in "${!cats[@]}"; do [[ "${cats[i]}" == "$active" ]] && break; done
  echo "${cats[(i + $1 + ${#cats[@]}) % ${#cats[@]}]}" >"$FZP_TAB"
}

pick_main() {
  local entries switch label choice file
  enter_templates_dir
  export FZP_TAB
  FZP_TAB="$(mktemp)"
  trap 'rm -f "$FZP_TAB"' EXIT
  echo all >"$FZP_TAB"

  entries="$(list)"
  [[ -n "$entries" ]] || { echo "fzp: no templates in $templates_dir yet. \"fzp add\" saves one." >&2; exit 1; }

  switch="reload($FZP_SELF _list)+transform-footer($FZP_SELF _tabs)+first"
  label='transform-preview-label:f={1}; echo " ${f%.*} "'

  # Top to bottom: category tabs, list, search input, key hints
  choice="$(fzf_ui --delimiter='\t' --with-nth=2.. --freeze-left=2 --tabstop=1 --info=inline-right \
    --list-label=' FuzzyPaste ' --input-label=' search ' --footer-label=' categories ' \
    --footer="$(tabs)" --header='↵ copy  ·  tab / shift-tab switch category  ·  esc quit' \
    --preview="$FZP_SELF _preview {1} {q}" \
    --bind "focus:$label" --bind "result:$label" --bind 'change:refresh-preview' \
    --bind "tab:execute-silent($FZP_SELF _cycle 1)+$switch" \
    --bind "shift-tab:execute-silent($FZP_SELF _cycle -1)+$switch" \
    <<<"$entries")" || exit 0

  file="${choice%%$'\t'*}"
  # Drop the description line and any blank lines right after it
  tail -n +2 "$file" | sed '/./,$!d' | copy_to_clipboard
  echo "Copied '${file%.*}' to clipboard."
}
