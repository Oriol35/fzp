# FuzzyPaste (fzp)

Yet another fuzzy search tool. Store templates, commands and others inside plain text files.

It's main purpose is to be a **lightweight** TUI alternative for clipboard managers.

Main commands:
```
fzp          pick a template and copy it
fzp add      save a new template into a category
fzp config   show the settings, change the templates folder
fzp help     show the commands
```

## Requirements

- Linux with **bash** 4.4 or newer
- git
- fzf, preferably a recent version (tested with 0.67). Since packages can get too old, if the installer says so, download fzf from its [releases page](https://github.com/junegunn/fzf/releases).
- A clipboard tool: **wl-clipboard** (Wayland) or **xclip** (X11). Any tool works, really.

## Recommended:
- **gawk** (case-insensitive highlights in the preview)
- **bash-completion** (Tab completion for `fzp`)

I facilitated an install script for you to automate it's setup.

## Installation

```bash
git clone https://github.com/YOUR-USERNAME/fzp.git ~/.fzp
~/.fzp/install.sh
```

Then open a new terminal and run `fzp`.

The installer works for your user only (no `sudo`). It puts `fzp` in `~/.local/bin`, linked to `~/.fzp`, so keep that folder. It asks before changing anything, and keeps a backup of `~/.bashrc` when it edits it.

The installer script walks you through:

- replacing fzp if it's already installed
- adding `~/.local/bin` to your `PATH`, if it isn't there yet
- creating the config file, and the folder where your templates live
- copying the example templates into that folder

## Update

```bash
git -C ~/.fzp pull
```

That's all: the installed `fzp` runs the code in `~/.fzp`. If a new version changes the config file format, fzp tells you, and `fzp config` updates the file.

## Uninstall

```bash
~/.fzp/uninstall.sh
rm -rf ~/.fzp
```

The uninstaller asks before each change: removing fzp, removing the `PATH` line the installer added, and deleting your config file (no by default). Your templates are never deleted: it tells you where they are, so you can keep or remove them yourself.

## Installer options

```
install.sh               install into ~/.local, linked to this folder ("git pull" here updates fzp)
install.sh --copy        copy fzp instead, so this folder can be deleted afterwards
install.sh --prefix DIR  install into DIR instead of ~/.local
install.sh --uninstall   same as uninstall.sh
```

With `--copy`, updating means pulling and running `install.sh --copy` again.

## Templates

Templates live in your templates folder (by default `~/.local/share/fzp`). Each subfolder is a category, and each `.md` or `.txt` file inside it is a template:

```
~/.local/share/fzp/
├── prompts/
│   └── explain-like-senior.md
└── templates/
    └── code-review.md
```

The first line of a template is its description, shown in the list. Everything below it is what gets copied:

```
# Review code for bugs, readability and edge cases

Review the following code. Focus on:
...
```

You can create these files by hand, or run `fzp add`, which walks you through the steps.

Your templates folder is just a folder: you can keep it in a synced folder (Dropbox, Syncthing) or in a git repository of its own to share your templates between computers.

## Config

`fzp config` shows where the config file is (`~/.config/fzp/config`) and which folder holds your templates, and lets you change that folder, offering to move your templates there. With no config file yet, it offers to create one.

The file holds one `key = value` per line. Comments go on their own line:

```
# Folder holding the templates; each subfolder is a category
templates_dir = ~/.local/share/fzp
```

The `FZP_TEMPLATES_DIR` environment variable overrides `templates_dir`.
