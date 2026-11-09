# FuzzyPaste (fzp)

A small clipboard manager for your terminal, for the long text you paste again and again: prompts, tricky
commands, templates. Each one of them is a plain text file inside a directory.

Find with fuzzy search in order to dave it into the clipboard.

```
fzp              pick a template and copy it
fzp add          save a new template into a category
fzp config       show the settings, change the templates folder
fzp uninstall    remove fzp
fzp help         show help (also -h, --help)
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

### Installer

Works for your user only (no `sudo`), and asks every question before it changes anything. It installs the latest release into the usual per-user folders:

| What | Where |
|---|---|
| `fzp` command | `~/.local/bin/fzp` |
| source code | `~/.local/lib/fzp/` |
| bash-completion | `~/.local/share/bash-completion/completions/fzp` |
| settings | `~/.config/fzp/config` |
| templates | `~/.local/share/fzp/` by default; customizable |

If `~/.local/bin` isn't on your `PATH`, it offers to add it in `~/.bashrc` (keeping a backup in
`~/.bashrc.fzp-backup`). It also offers to copy the example templates into your templates folder.

> From a clone of this repository, `./install.sh` installs that copy instead.

## Requirements

- Linux with **bash** 4.4 or newer
- **curl** for the installer
- **fzf** 0.67 or newer. Many distributions ship an older one!
   - If yours is missing or
  too old, the installer offers to download fzf's official release, checks it against fzf's published
  checksums, and keeps it in `~/.local/lib/fzp/` for fzp alone: it isn't put on your `PATH`.
- A clipboard tool: **wl-clipboard** (Wayland), or **xclip** or **xsel** (X11)
- **Recommended**: **gawk** (case-insensitive highlights in the preview) and **bash-completion** (Tab completion)

The installer checks for all of these and tells you what's missing.

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

Any plain-text extension works: `.md`, `.txt`, `.sh`, `.sql`…

> Pick the one that gives your editor the right highlighting.

### The first line of a template is the description. Everything after that is what gets copypasted, exactly as it is in the file:

```
# Email cordial salute for university ^-^

Dear [PROFESSOR],
...
```

A `#` first line works for most kinds of files. That's the reason it's **recommended**, but not obliged.

As a convention, it is recommended to write placeholders `[UPPERCASE SLOTS]`, like `[PASTE CODE/REFERENCES]`.

Create templates by hand, or with `fzp add`. It takes the text from the clipboard, or a buffer via a step by step guide.

> The templates directory has **no logic inside**. You can soft-link it or make it a git repository of its own.

## Config

`fzp config` shows where the config file and your templates are, and lets you choose another templates folder.
It offers to move your templates there, and to delete the old folder if anything is left in it.

The config file holds one `key = value` per line, and comments on lines of their own:

```
# Folder holding the templates; each subdirectory after that represents a category
templates_dir = ~/.local/share/fzp
```

`fzp help` always shows both locations.

## Update

Just run the installer again. Keeps your settings and templates intact.

## Uninstall

```bash
fzp uninstall
```

It removes fzp and the line it added to `~/.bashrc`. It asks separately before deleting your config file or your
templates (no by default).

## License

GPL-3.0. See [LICENSE](LICENSE).
