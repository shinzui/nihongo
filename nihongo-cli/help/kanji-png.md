# kanji png

`nihongo kanji png <KANJI>` rasterises a single kanji's KanjiVG SVG to a
PNG, caches the PNG on disk, and prints the absolute path to the cached
file on stdout. The kanji can be passed as a positional argument or
piped on stdin:

  nihongo kanji png 漢
  echo 漢 | nihongo kanji png

On success, stdout contains exactly one line: the absolute path to the
PNG. Exit status is 0. On any failure (KanjiVG not found, kanji not in
the corpus, `rsvg-convert` missing, etc.), an error message is written
to stderr and the command exits 1; stdout is left empty so command
substitution in shells fails loudly rather than feeding a bogus path
to the next tool.

The cache lives under `$XDG_CACHE_HOME/nihongo/strokes/` (or
`~/.cache/nihongo/strokes/` if `XDG_CACHE_HOME` is unset). Files are
named by the SHA-256 of the source SVG, so cache entries are shared
with the inline image rendered by `nihongo kanji show`. To clear the
cache, remove the directory; it will be recreated on demand.

Use `--kanjivg-dir PATH` to point at an alternate KanjiVG checkout
(the default is the git submodule at `data/kanjivg/`).

## Common uses

Open the PNG in an image viewer:

  open "$(nihongo kanji png 漢)"
  imv "$(nihongo kanji png 漢)"

Copy it somewhere:

  cp "$(nihongo kanji png 漢)" ~/Desktop/

Embed it in markdown:

  ![漢]($(nihongo kanji png 漢))

## Requirements

- The KanjiVG submodule must be initialised:
  `git submodule update --init data/kanjivg`.
- The system tool `rsvg-convert` (from `librsvg`) must be on `PATH`.
  The Nix devshell provides it via `pkgs.librsvg`.
