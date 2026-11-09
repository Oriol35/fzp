# Start a bash script: strict mode, usage, argument parsing and cleanup on exit
#!/usr/bin/env bash
# [SCRIPT NAME]: [WHAT IT DOES]
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: [SCRIPT NAME] [-h] [--] ARGS...

[WHAT IT DOES]

  -h, --help   show this help
EOF
}

main() {
  local args=()
  while (( $# )); do
    case "$1" in
      -h | --help) usage; exit 0 ;;
      --) shift; args+=("$@"); break ;;
      -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  # A scratch folder, removed on exit even after an error
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # [YOUR CODE], with the arguments in "${args[@]}"
}

main "$@"
