#!/usr/bin/env bash
# Uninstalls FuzzyPaste (fzp): the same as `install.sh --uninstall`, which does the work. Asks
# before each change; your templates are never deleted. Takes --prefix DIR like the installer.
exec bash "$(dirname "$(realpath "$0")")/install.sh" --uninstall "$@"
