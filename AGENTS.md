## Dotfiles

- Any structural change to this repo (adding, moving, or removing directories, files, symlink targets, or `dotfiles.yml` keys) must be reflected in the structure tree in `README.md`. Directories listed with a wildcard (e.g., `bin/*`) don't need every file enumerated because new files under them are already covered.
- Keys in `vscode/settings.json` must be in alphabetical order. When adding or moving a key, place it at the correct sorted position. Keys wrapped in non-alpha symbols (e.g., `[dart]`) are sorted by their first alpha character (so `[dart]` sorts as `dart`).
- A test may read real repo files; only one test may ever write into the repo working tree for a given path, and it must restore what it changed. Use the `mktemp -d` world `tests/helpers/setup.bash` already provides for everything else.
