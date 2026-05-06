# kanji show

`nihongo kanji show <KANJI>` displays the stroke order for a single Japanese
character. The character can be a kanji, hiragana, or katakana, and may be
passed as a positional argument or piped via stdin:

  nihongo kanji show 漢
  echo 漢 | nihongo kanji show

The output has two parts:

  1. A textual breakdown — one line per stroke, numbered, with the CJK Stroke
     character and an English description (e.g. "1. ㇔ dot").
  2. (In a Kitty-graphics-capable terminal) an inline image of the kanji
     rendered from KanjiVG. Otherwise a dim placeholder line.

Use `--format text` to skip the image entirely, `--format image` to skip the
text, or `--format both` (the default) to print both.

Use `--no-images` to suppress the inline image even when the terminal supports
it. Use `--kanjivg-dir PATH` to point at an alternate KanjiVG checkout (the
default is the git submodule at `data/kanjivg/`).

## Requirements

- The KanjiVG submodule must be initialised: `git submodule update --init data/kanjivg`.
- The system tool `rsvg-convert` (from `librsvg`) must be on `PATH` for image
  rendering. The Nix devshell provides it via `pkgs.librsvg`.
- For inline image rendering inside `tmux`, set `set -g allow-passthrough on`
  in your `~/.tmux.conf`.
