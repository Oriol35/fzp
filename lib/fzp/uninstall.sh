# `fzp uninstall`: remove what the installer put in place, and on request the PATH line, the config
# file and the templates folder. Asks everything first, then acts.

# The files and folders of an install in ~/.local that exist and are fzp's (a file of the same name
# from another program is left alone)
installed_files() {
  if [[ -L "$install_bin" ]] || grep -qs FuzzyPaste "$install_bin"; then echo "$install_bin"; fi
  if [[ -L "$install_lib" || -f "$install_lib/common.sh" ]]; then echo "$install_lib"; fi
  if [[ -L "$install_completion" ]] || grep -qs _fzp "$install_completion"; then echo "$install_completion"; fi
}

# Removes the installer's two lines from ~/.bashrc, after a backup. A symlinked ~/.bashrc (from a
# dotfiles folder) stays a symlink.
remove_path_line() {
  cp -- "$bashrc_file" "$bashrc_file.fzp-backup"
  sed -i --follow-symlinks "/^$bashrc_marker\$/,+1d" "$bashrc_file"
}

# Removes the folders in $@ that are empty, in that order
remove_empty_folders() {
  local dir
  for dir in "$@"; do rmdir -- "$dir" 2>/dev/null || true; done
}

uninstall_main() {
  local files=() f count status remove_path=n remove_config=n remove_templates=n
  mapfile -t files < <(installed_files)
  count="$(count_templates "$templates_dir")"
  printf '\n\e[1;36m FuzzyPaste · uninstall\e[0m\n\n'

  if (( ${#files[@]} )); then
    printf ' This removes:\n'
    for f in "${files[@]}"; do printf '     %s\n' "$(shorten_home "$f")"; done
    status=0
    ask "Uninstall fzp?" y || status=$?
    (( status == 0 )) || { config_nothing; return; }
  else
    warn_line "fzp isn't installed in $(shorten_home "$HOME/.local")."
  fi
  if grep -qsF "$bashrc_marker" "$bashrc_file"; then
    status=0
    ask "Remove the PATH line the installer added to ~/.bashrc?" y || status=$?
    (( status != 2 )) || { config_nothing; return; }
    (( status == 0 )) && remove_path=y
  fi
  if [[ -f "$config_file" ]]; then
    status=0
    ask "Delete your config file $(shorten_home "$config_file")?" n || status=$?
    (( status != 2 )) || { config_nothing; return; }
    (( status == 0 )) && remove_config=y
  fi
  if [[ -d "$templates_dir" && "$templates_dir" != / && "$templates_dir" != "$HOME" ]]; then
    status=0
    ask "Delete your templates folder $(shorten_home "$templates_dir") ($(plural "$count" template))?" n || status=$?
    (( status != 2 )) || { config_nothing; return; }
    (( status == 0 )) && remove_templates=y
  fi
  echo

  if (( ${#files[@]} )); then
    rm -rf -- "${files[@]}"
    remove_empty_folders "$(dirname "$install_lib")" "$(dirname "$install_completion")" \
      "$(dirname "$(dirname "$install_completion")")"
    ok_line "Removed fzp"
  fi
  if [[ "$remove_path" == y ]]; then
    remove_path_line
    ok_line "Removed the PATH line from ~/.bashrc (backup: ~/.bashrc.fzp-backup)"
  fi
  if [[ "$remove_config" == y ]]; then
    rm -f -- "$config_file"
    remove_empty_folders "$(dirname "$config_file")"
    ok_line "Deleted $(shorten_home "$config_file")"
  elif [[ -f "$config_file" ]]; then
    printf '   Kept your config file: %s\n' "$(shorten_home "$config_file")"
  fi
  if [[ "$remove_templates" == y ]]; then
    rm -rf -- "$templates_dir"
    ok_line "Deleted $(shorten_home "$templates_dir")"
  elif [[ -d "$templates_dir" ]]; then
    printf '   Kept your templates: %s (%s)\n' "$(shorten_home "$templates_dir")" "$(plural "$count" template)"
  fi
  echo
}
