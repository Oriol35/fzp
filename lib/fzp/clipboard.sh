# The clipboard: Windows' own on WSL, otherwise a Linux clipboard tool. Sourced, not run on its own.

# Exists on WSL when it can run Windows programs
fzp_wsl_interop=/proc/sys/fs/binfmt_misc/WSLInterop

# Where Windows keeps clip.exe and PowerShell, seen from WSL
fzp_windows_system32=/mnt/c/Windows/System32

is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" || -e "$fzp_wsl_interop" ]]; }

# Prints how to run the Windows program $1: by name when it's on PATH, or else from its usual place
# $2 under System32 (WSL can be set up not to add Windows' folders to PATH). Fails when it's neither.
windows_exe() {
  if command -v "$1" >/dev/null; then
    echo "$1"
  elif [[ -x "$fzp_windows_system32/$2" ]]; then
    echo "$fzp_windows_system32/$2"
  else
    return 1
  fi
}

# The tool fzp copies with, or fails when there's none. On WSL that's Windows' clip.exe: WSLg's Wayland
# clipboard doesn't reliably reach Windows programs. Elsewhere wl-copy on Wayland, else xclip, else xsel.
clipboard_tool() {
  if is_wsl && windows_exe clip.exe clip.exe; then
    return 0
  elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null; then
    echo wl-copy
  elif command -v xclip >/dev/null; then
    echo xclip
  elif command -v xsel >/dev/null; then
    echo xsel
  else
    return 1
  fi
}

no_clipboard_tool() {
  echo "fzp: no clipboard tool found. Install wl-clipboard (Wayland), xclip or xsel (X11)." >&2
  return 1
}

# Copies its input exactly as it is
copy_to_clipboard() {
  local tool
  tool="$(clipboard_tool)" || { no_clipboard_tool; return; }
  case "$tool" in
    # clip.exe reads UTF-16, and would turn accented letters into garbage otherwise
    *clip.exe) iconv -f UTF-8 -t UTF-16LE | "$tool" ;;
    wl-copy) wl-copy ;;
    xclip) xclip -selection clipboard ;;
    xsel) xsel --clipboard --input ;;
  esac
}

# Prints the clipboard's text exactly as it is (on WSL with Linux line endings), or nothing when it holds
# something else, such as an image
paste_from_clipboard() {
  local tool powershell
  tool="$(clipboard_tool)" || { no_clipboard_tool; return; }
  case "$tool" in
    *clip.exe)
      powershell="$(windows_exe powershell.exe WindowsPowerShell/v1.0/powershell.exe)" ||
        { echo "fzp: PowerShell wasn't found, so fzp can't read the Windows clipboard." >&2; return 1; }
      "$powershell" -NoProfile -NonInteractive -Command \
        '[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false; $t = Get-Clipboard -Raw; if ($t) { [Console]::Out.Write($t) }' \
        2>/dev/null | sed 's/\r$//' ;;
    wl-copy) wl-paste --no-newline --type text 2>/dev/null ;;
    xclip) xclip -selection clipboard -o 2>/dev/null ;;
    xsel) xsel --clipboard --output 2>/dev/null ;;
  esac
}
