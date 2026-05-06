# kanji show

`nihongo kanji show <KANJI>` displays the stroke order for one or more
Japanese characters. The input can be a single character, a multi-character
word, or a mix of kanji, hiragana, and katakana. It may be passed as a
positional argument or piped via stdin:

  nihongo kanji show 漢
  nihongo kanji show 漢字
  echo 食べる | nihongo kanji show

For each character, the output has two parts:

  1. A textual breakdown — one line per stroke, numbered, with the CJK Stroke
     character and an English description (e.g. "1. ㇔ dot").
  2. (In a Kitty-graphics-capable terminal) an inline image of the kanji
     rendered from KanjiVG. Otherwise a dim placeholder line.

Multi-character inputs print one section per character, in input order,
separated by a blank line.

Use `--format text` to skip the image entirely, `--format image` to skip the
text, or `--format both` (the default) to print both.

Use `--no-images` to suppress the inline image even when the terminal supports
it. Use `--kanjivg-dir PATH` to point at an alternate KanjiVG checkout (the
default is the git submodule at `data/kanjivg/`).

## Words

When you pass a word, every character is processed independently with the
same flags. A few specifics:

- Whitespace inside the input is stripped before parsing, so `食 べ る` and
  `食べる` produce the same three sections.
- Non-Japanese characters cause a hard error naming the offending codepoint
  (no silent skipping). For example, `nihongo kanji show "I食べる"` exits
  non-zero with `not a Japanese character: I`.
- KanjiVG misses are reported per character. The header line for the
  missing character is printed followed by `(no KanjiVG entry)`, and the
  rest of the word continues to render. The command exits non-zero only
  when *every* character was missing from KanjiVG.
- Each character renders an independent inline image; long words scroll.
  For terminal-friendly word study, pass `--format text`.

The textual stroke list now reads `<n>. <description>  <symbol>` where
the trailing CJK Stroke character (e.g. `㇔`, `㇑`, `㇏`) is rendered
dim. If your terminal font lacks glyphs for the CJK Strokes block
(U+31C0–U+31E3), the dim symbol may render as `?` or `\` — but the
description on the same line is unaffected.

## Requirements

- The KanjiVG submodule must be initialised: `git submodule update --init data/kanjivg`.
- The system tool `rsvg-convert` (from `librsvg`) must be on `PATH` for image
  rendering. The Nix devshell provides it via `pkgs.librsvg`.
- For inline image rendering inside `tmux`, set `set -g allow-passthrough on`
  in your `~/.tmux.conf`.

## Known limitations

The Kitty graphics protocol uses *absolute terminal coordinates*, not
pane-relative ones. Inside a tmux session with split panes, the inline
image will paint at the outer terminal's row 0 — visually appearing in
the top-most pane instead of the pane where you ran `kanji show`.
Workarounds: run in a single-pane tmux session, run outside tmux
entirely, or pass `--no-images` to suppress the image and rely on the
textual stroke order.
