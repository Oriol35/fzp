# FuzzyPaste (fzp)

A small clipboard manager for your terminal, for the long text you paste again and again: prompts, tricky
commands, replies. Each one is a plain text file in a folder. Find one with a fuzzy search, press Enter, and it's
on your clipboard.

```
fzp              pick a template and copy it
fzp add          save a new template into a category
fzp config       show the settings, change the templates folder
fzp uninstall    remove fzp
fzp help         show this help (also -h, --help)
fzp --version    show the version (also -V)
```

## Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Oriol35/fzp/main/install.sh)"
```

Or, to read the installer before running it:

```bash
curl -fsSLo install-fzp.sh https://raw.githubusercontent.com/Oriol35/fzp/main/install.sh
less install-fzp.sh
bash install-fzp.sh
```

The installer works for your user only (no `sudo`), and asks every question before it changes anything. It
installs the latest release into the usual per-user folders:

| What | Where |
|---|---|
| the `fzp` command | `~/.local/bin/fzp` |
| its code | `~/.local/lib/fzp/` |
| Tab completion | `~/.local/share/bash-completion/completions/fzp` |
| settings | `~/.config/fzp/config` |
| your templates | `~/.local/share/fzp/` by default; you choose |

If `~/.local/bin` isn't on your `PATH`, it offers to add it in `~/.bashrc` (keeping a backup in
`~/.bashrc.fzp-backup`). It also offers to copy the example templates into your templates folder.

From a copy of this repository, `./install.sh` installs that copy instead.

## Requirements

- Linux with **bash** 4.4 or newer, and **curl** for the installer
- **fzf** 0.67 or newer. Many distributions ship an older one (Ubuntu 24.04 has 0.44). If yours is missing or
  too old, the installer offers to download fzf's official release, checks it against fzf's published
  checksums, and keeps it in `~/.local/lib/fzp/` for fzp alone: it isn't put on your `PATH`.
- A clipboard tool: **wl-clipboard** (Wayland), or **xclip** or **xsel** (X11)
- Recommended: **gawk** (case-insensitive highlights in the preview) and **bash-completion** (Tab completion)

The installer checks all of these and tells you what's missing.

## Templates

Your templates folder holds one folder per category, and each text file inside is a template:

```
~/.local/share/fzp/
├── prompts/
│   ├── code-review.md
│   └── diagnose-bug.md
└── commands/
    ├── largest-dirs.sh
    └── http-timing.sh
```

Any plain-text extension works: `.md`, `.txt`, `.sh`, `.sql`… Pick the one that gives your editor the right
highlighting. The list shows names without it.

The first line of a template is its description, shown in the list. Everything below it is what gets copied,
exactly as it is in the file:

```
# Review code for bugs, readability and edge cases

Review the following code. Focus on:
...
```

A `#` first line works for most kinds of files: it's a heading in Markdown and a comment in shell scripts.

Parts you fill in after pasting are written as `[UPPERCASE SLOTS]`, like `[PASTE CODE/REFERENCES]`. That's
only a convention to make them easy to spot: fzp copies them as they are.

Create templates by hand, or with `fzp add`, which takes the text from the clipboard, your editor, or what you
type, and walks you through the description, the category and the file name.

The examples show two good uses: prompts you send to an AI, and commands that are useful but hard to remember
(`commands/largest-dirs.sh`, `commands/http-timing.sh`, `commands/duplicate-files.sh`…).

Your templates folder is just a folder, so you can keep it in a synced folder or in a git repository of its own.

## Config

`fzp config` shows where the config file and your templates are, and lets you choose another templates folder.
It offers to move your templates there, and to delete the old folder if anything is left in it.

The config file holds one `key = value` per line, and comments on lines of their own:

```
# Folder holding the templates; each subfolder is a category
templates_dir = ~/.local/share/fzp
```

`fzp help` always shows where both are.

## Update

Run the installer again. It keeps your settings and your templates.

## Uninstall

```bash
fzp uninstall
```

It removes fzp and the line it added to `~/.bashrc`. It asks separately before deleting your config file or your
templates (no by default).

## License

GPL-3.0. See [LICENSE](LICENSE).
