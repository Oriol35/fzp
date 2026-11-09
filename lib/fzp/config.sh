# `fzp config`: show the config file and the templates folder, and offer to change the folder,
# moving the templates there and, if anything is left behind, deleting the old folder. With no
# config file yet, offer to create one. Every question comes before any change, so cancelling
# (Ctrl-C or Ctrl-D) changes nothing.

config_nothing() { echo " Nothing was changed."; }

# Writes the config file pointing at $1 and creates that folder when needed
save_config() {
  write_config "$1"
  ok_line "Saved $(shorten_home "$config_file")"
  if [[ ! -d "$1" ]]; then
    mkdir -p "$1"
    ok_line "Created the templates folder $(shorten_home "$1")"
  fi
}

# Everything in folder $1 that would stay there after move_templates "$1" "$2": templates whose
# place in $2 is taken, and files that aren't templates. One path per line, relative to $1.
templates_left_behind() {
  local old="$1" new="$2" f
  local -A moving=()
  while IFS= read -r f; do
    [[ -e "$new/$f" ]] || moving["$f"]=1
  done < <(cd "$old" && template_files)
  while IFS= read -r f; do
    [[ -n "${moving[$f]:-}" ]] || printf '%s\n' "$f"
  done < <(cd "$old" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n') | sort
}

# Moves the templates in folder $1 to the same place in folder $2, unless that place is taken.
# Then removes the folders left empty, the old folder included. With $3 = deleting, the old folder
# is about to be deleted, so what stays there isn't mentioned.
move_templates() {
  local old="$1" new="$2" f moved=0 kept=0
  while IFS= read -r f; do
    if [[ -e "$new/$f" ]]; then
      kept=$((kept + 1))
    else
      mkdir -p "$new/${f%/*}"
      mv -- "$old/$f" "$new/$f"
      moved=$((moved + 1))
    fi
  done < <(cd "$old" && template_files)
  find "$old" -depth -type d -empty -delete 2>/dev/null || true
  ok_line "Moved $(plural "$moved" template) to $(shorten_home "$new")"
  if (( kept )) && [[ "${3:-}" != deleting ]]; then
    warn_line "$kept stayed in $(shorten_home "$old"): the new folder already has a template with the same name."
  fi
}

# True when folders $1 and $2 are the same folder, even under another name (a symlink, or other
# letter case on a Windows drive), or when one is inside the other
same_or_nested() {
  local a b
  [[ -e "$1" && -e "$2" && "$1" -ef "$2" ]] && return 0
  a="$(realpath -m -- "$1")/"
  b="$(realpath -m -- "$2")/"
  [[ "$a" == "$b"* || "$b" == "$a"* ]]
}

# Lists the paths on its input, at most 10, indented
show_some() {
  local lines
  mapfile -t lines
  printf '     %s\n' "${lines[@]:0:10}"
  (( ${#lines[@]} <= 10 )) || printf '     …and %d more\n' $(( ${#lines[@]} - 10 ))
}

# Shows the current settings and offers to change the templates folder
change_config() {
  local old="$templates_dir" new count left move=n delete=n status
  count="$(count_templates "$old")"
  printf ' Config file:      %s\n' "$(shorten_home "$config_file")"
  printf ' Templates folder: %s (%s)\n\n' "$(shorten_home "$old")" "$(plural "$count" template)"

  status=0
  ask "Change the templates folder?" n || status=$?
  (( status == 0 )) || { config_nothing; return; }
  ask_folder "$old" || { config_nothing; return; }
  new="$answer_dir"
  [[ "$new" != "$old" ]] || { config_nothing; return; }
  if [[ -e "$new" && "$new" -ef "$old" ]]; then
    warn_line "$(shorten_home "$new") is the folder you already use, under another name."
    config_nothing
    return
  fi
  if [[ -e "$new" && ! -d "$new" ]]; then
    warn_line "$(shorten_home "$new") is a file, not a folder."
    config_nothing
    return
  fi

  if (( count > 0 )); then
    if same_or_nested "$old" "$new"; then
      warn_line "One folder is inside the other, so your templates can't be moved automatically."
    else
      status=0
      ask "Move your $(plural "$count" template) to $(shorten_home "$new")?" y || status=$?
      (( status != 2 )) || { config_nothing; return; }
      (( status == 0 )) && move=y
    fi
  fi

  if [[ "$move" == y ]]; then
    left="$(templates_left_behind "$old" "$new")"
    if [[ -n "$left" ]]; then
      echo
      printf ' These would stay in %s:\n' "$(shorten_home "$old")"
      show_some <<<"$left"
      status=0
      ask "Delete the old folder and everything left in it?" n || status=$?
      (( status != 2 )) || { config_nothing; return; }
      (( status == 0 )) && delete=y
    fi
  fi

  echo
  save_config "$new"
  if [[ "$move" == y ]]; then
    move_templates "$old" "$new" "$([[ "$delete" == y ]] && echo deleting)"
    if [[ "$delete" == y && "$old" != / && "$old" != "$HOME" ]]; then
      rm -rf -- "$old"
      ok_line "Deleted $(shorten_home "$old")"
    fi
  elif (( count > 0 )); then
    printf '   Your %s stay in %s.\n' "$(plural "$count" template)" "$(shorten_home "$old")"
  fi
}

# No config file yet: offer to create one
create_config() {
  local status=0
  ask "No config file yet. Create $(shorten_home "$config_file")?" y || status=$?
  (( status == 0 )) || { config_nothing; return; }
  printf '\n Which folder should hold your templates? Press Enter to accept, or edit it.\n'
  ask_folder "$templates_dir" || { config_nothing; return; }
  echo
  save_config "$answer_dir"
  (( $(count_templates "$answer_dir") > 0 )) || printf '   Run "fzp add" to save your first template.\n'
}

config_main() {
  # Without a terminal (scripts) only the path is printed
  if [[ ! -t 0 || ! -t 1 ]]; then
    if [[ -f "$config_file" ]]; then
      echo "$config_file"
      return
    fi
    echo "fzp: there is no config file yet. Run \"fzp config\" in a terminal to create one." >&2
    exit 1
  fi
  trap 'echo; config_nothing; exit 0' INT
  printf '\n\e[1;36m FuzzyPaste · config\e[0m\n\n'
  if [[ -f "$config_file" ]]; then
    change_config
  else
    create_config
  fi
}
