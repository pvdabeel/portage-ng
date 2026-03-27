# Shell assets

Shell integration files for portage-ng.

## Completion/

Tab-completion scripts for interactive shells.

| File | Shell | Install |
|------|-------|---------|
| `portage-ng.bash` | Bash | `source` it or copy to `/etc/bash_completion.d/` |
| `portage-ng.zsh` | Zsh | `source` it or copy to a directory in `$fpath` |

## Profile/

Example shell profile snippets that define the `portage-ng-dev` alias
for running portage-ng from a source checkout.

| File | Shell |
|------|-------|
| `.bash_profile` | Bash |
| `.zshrc` | Zsh |

Edit the `/path/to/prolog` placeholder to match your checkout location,
then add the alias to your shell profile. Alternatively, use the wrapper
script at `Source/Application/System/Scripts/Wrapper/portage-ng-dev`
which requires no alias setup.
