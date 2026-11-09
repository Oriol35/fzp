# `fzp config`: show the config file and the templates folder, and offer to change the folder
# (moving the templates there too). When there's no config file yet, offer to create one. Every
# question comes before any change, so cancelling changes nothing.

config_nothing() { echo " Nothing was changed."; }

# "1 template", "3 templates"
plural() { if (( $1 == 1 )); then echo "1 $2"; else echo "$1 $2s"; fi; }

# Writes the config file pointing at $1 and creates that folder when needed
save_config() {
  write_config "$1"
  printf '\n\e[32m ✓\e[0m Saved %s\n' "$(shorten_home "$config_file")"
  if [[ ! -d "$1" ]]; then
    mkdir -p "$1"
    printf '\e[32m ✓\e[0m Created the templates folder %s\n' "$(shorten_home "$1")"
  fi
}

# Moves the templates in folder $1 into folder $2, category by category. A template whose name is
# already taken in $2 stays where it is. Folders left empty are removed.
move_templates() {
  local from="$1" to="$2" cat_dir category f moved=0 kept=0
  while IFS= read -r cat_dir; do
    category="${cat_dir#"$from"/}"
    mkdir -p "$to/$category"
    while IFS= read -r f; do
      if [[ -e "$to/$category/$f" ]]; then
        kept=$((kept + 1))
      else
        mv "$cat_dir/$f" "$to/$category/$f"
        moved=$((moved + 1))
      fi
    done < <(find "$cat_dir" -maxdepth 1 -type f -not -name '.*' \( -name '*.md' -o -name '*.txt' \) -printf '%f\n')
    rmdir "$cat_dir" 2>/dev/null || true
  done < <(find "$from" -mindepth 1 -maxdepth 1 -type d -not -name '.*')
  rmdir "$from" 2>/dev/null || true
  printf '\e[32m ✓\e[0m Moved %s into %s\n' "$(plural "$moved" template)" "$(shorten_home "$to")"
  if (( kept )); then
    printf '\e[33m ⚠\e[0m %s stayed in %s: a template with the same name is already in the new folder.\n' \
      "$kept" "$(shorten_home "$from")"
  fi
}

# Shows the current settings and offers to change the templates folder
change_config() {
  local old="$templates_dir" count move=n status
  count="$(count_templates "$old")"
  printf ' Config file:      %s\n' "$(shorten_home "$config_file")"
  printf ' Templates folder: %s (%s)\n\n' "$(shorten_home "$old")" "$(plural "$count" template)"

  status=0
  ask "Change the templates folder?" n || status=$?
  (( status == 0 )) || { config_nothing; return; }
  ask_folder "$old" || { config_nothing; return; }
  [[ "$answer_dir" != "$old" ]] || { config_nothing; return; }

  if (( count > 0 )); then
    if [[ "$answer_dir/" == "$old/"* || "$old/" == "$answer_dir/"* ]]; then
      printf '\e[33m ⚠\e[0m One folder is inside the other, so your templates can'"'"'t be moved automatically.\n'
    else
      status=0
      ask "Move your $(plural "$count" template) to $(shorten_home "$answer_dir")?" y || status=$?
      (( status != 2 )) || { config_nothing; return; }
      (( status == 0 )) && move=y
    fi
  fi

  save_config "$answer_dir"
  if [[ "$move" == y ]]; then
    move_templates "$old" "$answer_dir"
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
