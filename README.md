# nihongo

Study Japanese stroke order from the terminal. `nihongo` shows numbered stroke
lists and diagrams for individual characters or whole words, including kanji,
hiragana, and katakana covered by KanjiVG.

## Quick start

From the repository root, use Nix to run the CLI with its packaged KanjiVG data.

```sh
nix run . -- kanji show --format text 漢字
```

Use `nix shell .` to put `nihongo` on `PATH` for the examples below, or
`nix build .` to build `./result/bin/nihongo`. Inline diagrams and PNG export
require `rsvg-convert` from `librsvg` on `PATH`. The Nix development shell
provides it.

## Usage

```sh
nihongo kanji show 漢字
printf '%s\n' 食べる | nihongo kanji show --format text
nihongo kanji show --format image --image-theme dark 漢字
nihongo kanji png 漢
```

- `kanji show` reads a character or word from an argument or stdin. Its default
  `--format both` shows the diagram beside each stroke list when space allows.
  `--format text` prints only the stroke lists. `--format image` lays out diagrams
  in rows when terminal geometry is available, wrapping to fit the width.
- Inline images use the Kitty graphics protocol, with detection for Kitty,
  WezTerm, Ghostty, and Rex. The default `--image-theme light` keeps the
  original KanjiVG colors. Use `--image-theme dark` for light strokes and
  numbers, or `--no-images` to disable inline rendering. Inside tmux, inline
  images require `set -g allow-passthrough on` in `~/.tmux.conf`.
- `kanji png` accepts a single character and prints the absolute path to its
  cached PNG. The cache lives in `$XDG_CACHE_HOME/nihongo/strokes`, defaulting to
  `~/.cache/nihongo/strokes`.

Run `nihongo help` for topics, including `kanji-show` and `kanji-png`. Run
`nihongo completions zsh` to generate a completion script. Bash (`bash`) and
Fish (`fish`) are also supported.

### Aliases

Put shortcuts in `$XDG_CONFIG_HOME/nihongo/config.kdl`, which defaults to
`~/.config/nihongo/config.kdl`.

```kdl
aliases {
  ks "kanji show --image-theme dark"
}
```

Run `nihongo ks 漢字` to use the alias, `nihongo alias list` to list configured
aliases, and `nihongo help aliases` for the configuration reference.

## Development

Initialize the KanjiVG submodule and enter the Nix development shell, which
provides GHC 9.12.4 and Cabal.

```sh
git submodule update --init --depth 1 data/kanjivg
nix develop
cabal build all
cabal test all
cabal run nihongo -- kanji show --format text 漢字
```

- `nihongo-core` contains the Japanese character types, KanjiVG lookup,
  stroke-order parsing, and configuration.
- `nihongo-cli` provides the `nihongo` executable, terminal rendering, and PNG
  caching.

### KanjiVG data

Cabal builds look for `data/kanjivg` relative to the working directory. The
submodule is pinned to KanjiVG release `r20250816`. Nix builds default to the
KanjiVG revision pinned in `flake.lock` and can use it from any working directory.
For either build, use `--kanjivg-dir PATH` on a kanji command or set
`NIHONGO_KANJIVG_DIR` to use another KanjiVG checkout. The checkout must contain
a `kanji/` directory.

## License

nihongo is licensed under [BSD-3-Clause](./LICENSE). The KanjiVG corpus is
licensed under CC BY-SA 3.0. See `data/kanjivg/COPYING` for its license text.
