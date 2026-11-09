# `fzp config`: show the config file and the templates folder, and offer to change the folder
# (moving the templates there too). When there's no config file yet, offer to create one. Every
# question comes before any change, so cancelling changes nothing.

# The config file `fzp config` writes, with $1 as the templates folder
default_config() {
  cat <<EOF
# FuzzyPaste settings: one "key = value" per line, no quotes needed.
# The FZP_TEMPLATES_DIR environment variable overrides the folder set here.

# Folder holding the templates; each subfolder is a category
templates_dir = $1
EOF
}

config_nothing() { echo " Nothing was changed."; }

# Stopping after the file was updated (change_config's $updated) only leaves the folder as it is
config_stop() {
  if (( ${updated:-0} )); then echo " The templates folder stays the same."; else config_nothing; fi
}

# "1 template", "3 templates"
plural() { if (( $1 == 1 )); then echo "1 $2"; else echo "$1 $2s"; fi; }

# Asks for the templates folder, prefilled with $1. Sets new_dir to its absolute path (a relative
# one would depend on where fzp is run from); fails when the user cancels.
ask_templates_dir() {
  local dir=""
  while [[ -z "$dir" ]]; do
    read -r -e -i "$(shorten_home "$1")" \
      -p $'\001\e[1;36m\002 Templates folder:\001\e[0m\002 ' dir || { echo; return 1; }
    dir="$(trim "$dir")"
  done
  new_dir="$(realpath -m "$(expand_home "$dir")")"
}

# Yes/no question; $2 is the answer Enter gives (y or n). Returns 0 for yes, 1 for no and 2 when
# the user cancels with Ctrl-D.
config_ask() {
  local answer hint="[Y/n]"
  [[ "$2" == n ]] && hint="[y/N]"
  read -r -p " $1 $hint " answer || { echo; return 2; }
  [[ "${answer:-$2}" == [yY]* ]]
}

# Writes the config file pointing at $1 and creates that folder when needed
save_config() {
  mkdir -p "$(dirname "$config_file")"
  default_config "$(shorten_home "$1")" >"$config_file"
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

# Explains what's outdated or unknown in the config file
outdated_notice() {
  local key changes=()
  for key in "${old_settings[@]}"; do
    case "$key" in
      library) changes+=('"library" is now called "templates_dir"') ;;
      height) changes+=('"height" is no longer used') ;;
    esac
  done
  if (( ${#changes[@]} )); then
    printf '\e[33m ⚠\e[0m This config file is from an older fzp: %s.\n' "$(IFS=';'; echo "${changes[*]}" | sed 's/;/; /g')"
  fi
  for key in "${unknown_settings[@]}"; do
    printf '\e[33m ⚠\e[0m "%s" isn'"'"'t a setting fzp knows (a typo?). Updating the file removes it.\n' "$key"
  done
}

# Shows the current settings, offers to update an outdated file and to change the templates folder
change_config() {
  local old="$templates_dir_setting" count move=n status updated=0
  count="$(count_templates "$old")"
  printf ' Config file:      %s\n' "$(shorten_home "$config_file")"
  printf ' Templates folder: %s (%s)\n' "$(shorten_home "$old")" "$(plural "$count" template)"
  printf '\e[2m fzp always reads its config from this file.\e[0m\n'
  if [[ -n "${FZP_TEMPLATES_DIR:-}" ]]; then
    printf '\e[33m ⚠\e[0m FZP_TEMPLATES_DIR is set, so fzp uses %s instead of the folder above.\n' \
      "$(shorten_home "$templates_dir")"
  fi
  echo

  # A file from an older fzp, or with settings fzp doesn't know: offer to rewrite it
  if (( ${#old_settings[@]} + ${#unknown_settings[@]} )); then
    outdated_notice
    status=0
    config_ask "Update the file? Your templates folder stays the same." y || status=$?
    (( status != 2 )) || { config_nothing; return; }
    if (( status == 0 )); then
      save_config "$old"
      updated=1
      echo
    fi
  fi

  status=0
  config_ask "Change the templates folder?" n || status=$?
  (( status == 0 )) || { config_stop; return; }
  ask_templates_dir "$old" || { config_stop; return; }
  [[ "$new_dir" != "$old" ]] || { config_stop; return; }

  if (( count > 0 )); then
    if [[ "$new_dir/" == "$old/"* || "$old/" == "$new_dir/"* ]]; then
      printf '\e[33m ⚠\e[0m One folder is inside the other, so your templates can'"'"'t be moved automatically.\n'
    else
      status=0
      config_ask "Move your $(plural "$count" template) to $(shorten_home "$new_dir")?" y || status=$?
      (( status != 2 )) || { config_stop; return; }
      (( status == 0 )) && move=y
    fi
  fi

  save_config "$new_dir"
  if [[ "$move" == y ]]; then
    move_templates "$old" "$new_dir"
  elif (( count > 0 )); then
    printf '   Your %s stay in %s.\n' "$(plural "$count" template)" "$(shorten_home "$old")"
  fi
}

# No config file yet: offer to create one
create_config() {
  local status=0
  config_ask "No config file yet. Create $(shorten_home "$config_file")?" y || status=$?
  (( status == 0 )) || { config_nothing; return; }
  printf '\n Which folder should hold your templates? Press Enter to accept, or edit it.\n'
  ask_templates_dir "$templates_dir_setting" || { config_nothing; return; }
  save_config "$new_dir"
  (( $(count_templates "$new_dir") > 0 )) || printf '   Run "fzp add" to save your first template.\n'
}

config_main() {
  # Without a terminal (scripts, the installer) only the path is printed
  if [[ ! -t 0 || ! -t 1 ]]; then
    if [[ -f "$config_file" ]]; then
      echo "$config_file"
      return
    fi
    echo "fzp: there is no config file yet. Run \"fzp config\" in a terminal to create one." >&2
    exit 1
  fi
  trap 'echo; config_stop; exit 0' INT
  printf '\n\e[1;36m FuzzyPaste · config\e[0m\n\n'
  if [[ -f "$config_file" ]]; then
    change_config
  else
    create_config
  fi
}
