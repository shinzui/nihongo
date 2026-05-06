---
id: 7
slug: add-kanji-png-subcommand-and-library-function-returning-a-cached-png-path-for-a-kanji
title: "Add kanji png subcommand and library function returning a cached PNG path for a kanji"
kind: exec-plan
created_at: 2026-05-06T04:30:33Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
---

# Add kanji png subcommand and library function returning a cached PNG path for a kanji

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan a user — or a downstream caller — can ask `nihongo` for the
filesystem path of a PNG that depicts a single kanji's KanjiVG glyph, without
having to know anything about the underlying corpus, the cache layout, or the
SVG-to-PNG rasterisation step.

Two new affordances are introduced. The first is a typed Haskell function:

    Nihongo.Kanji.Png.kanjiPngPath
      :: KanjiPngOptions
      -> Nihongo.Kanji.Kanji
      -> IO (Either KanjiPngError FilePath)

Given a `Kanji` (`Nihongo.Kanji` from `nihongo-core`), it resolves the KanjiVG
checkout on disk, locates that kanji's SVG, rasterises it to PNG (or returns an
existing cache entry), and yields the absolute path to that PNG. The cache is
the same one EP-4 introduced — `<XDG_CACHE_HOME or ~/.cache>/nihongo/strokes/<sha256>.png`,
keyed by SHA-256 of the SVG's bytes — so this function shares cache hits with the
inline-image rendering path used by `nihongo kanji show`.

The second is a CLI subcommand:

    nihongo kanji png 漢

prints, on stdout, a single line containing the absolute path to that PNG, and
exits zero:

    /Users/shinzui/.cache/nihongo/strokes/b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9.png

Like `kanji show`, the kanji can be passed positionally (`nihongo kanji png 漢`)
or piped on stdin (`echo 漢 | nihongo kanji png`), and `--kanjivg-dir PATH`
overrides the KanjiVG checkout location. On any error (missing corpus, kanji
not in KanjiVG, `rsvg-convert` missing, etc.) the command writes a
human-readable message to stderr and exits 1; stdout stays empty so callers
piping the result into another tool fail loudly rather than silently using a
bogus path.

You will know this is working when the four invocation forms in
*Validation and Acceptance* below all produce the documented outputs, including
the round-trip through `cat`:

    cat "$(cabal run -v0 nihongo -- kanji png 漢)" | file -

reports `PNG image data, 109 x 109, 8-bit/color RGBA, non-interlaced`.

This plan adds no new system dependency: `rsvg-convert` (from `librsvg`,
declared in `flake.nix` since EP-1) is already required by the existing inline
image path.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone A: Add `Nihongo.Kanji.Png` library module exporting `KanjiPngOptions`, `KanjiPngError`, and `kanjiPngPath`.
- [ ] Milestone B: Add `Nihongo.Cli.Commands.Kanji.Png` subcommand and wire it into `Nihongo.Cli.Commands.Kanji.kanjiParser`.
- [ ] Milestone C: Add `nihongo-cli/help/kanji-png.md` and register it in `Nihongo.Cli.Help.helpTopics`.
- [ ] Milestone D: End-to-end manual verification of every invocation form listed in *Validation and Acceptance*.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Place the new library function in a new module `Nihongo.Kanji.Png`
  *inside the `nihongo-cli` package*, next to `Nihongo.Terminal.Image`, rather
  than promoting it to `nihongo-core`.
  Rationale: The function's only non-trivial dependency is `ensurePng` from
  `Nihongo.Terminal.Image`, which already brings in `process`,
  `cryptohash-sha256`, `base64-bytestring`, and `unix`. Promoting any of those
  to `nihongo-core` (currently a pure-data, no-IO-dep-besides-`xml-conduit`
  package) would widen the core surface area for the benefit of one consumer.
  If a future non-CLI caller (e.g. an MCP server, a future `nihongo-server`
  package) needs the function, the file is a single move-and-rename away.
  Date: 2026-05-05.

- Decision: The new subcommand is `nihongo kanji png <KANJI>`, slotting into the
  `kanji` subcommand group introduced by EP-5 alongside `kanji show`.
  Rationale: The user model is "operations on a kanji"; `show` and `png` are
  two such operations. Future siblings (`kanji find`, `kanji components`) will
  follow the same pattern. Putting it under `kanji` keeps `nihongo --help`
  uncluttered and makes the help-text discovery path obvious
  (`nihongo kanji --help` lists both).
  Date: 2026-05-05.

- Decision: On error, write a human-readable message to stderr and exit 1;
  leave stdout empty.
  Rationale: The whole point of the subcommand is to be safe to substitute into
  shell pipelines (`cp "$(nihongo kanji png 漢)" /tmp/`, `imv "$(...)"`, etc.).
  If errors leaked onto stdout the substitution would feed garbage to the next
  tool. Empty stdout + non-zero exit is the universally understood "no path,
  don't use my output" signal.
  Date: 2026-05-05.

- Decision: Do *not* add a `--no-images` or `--format` flag.
  Rationale: The user invoked `kanji png` explicitly to obtain a PNG path.
  Adding a switch that suppresses rasterisation would be a UX paradox. The
  capability-detection logic from EP-4 is irrelevant here because we are not
  emitting any escape sequences — we are producing a filesystem path.
  Date: 2026-05-05.

- Decision: Reuse EP-4's existing cache (`~/.cache/nihongo/strokes/<sha>.png`)
  rather than introducing a separate cache namespace.
  Rationale: A second invocation of `nihongo kanji show 漢` after
  `nihongo kanji png 漢` should be instantaneous, and vice versa. The cache
  key is already content-derived (SHA-256 of the SVG bytes), so cross-consumer
  sharing is safe and cheap.
  Date: 2026-05-05.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan assumes the repository is in the state left by EP-1 through EP-5
(`docs/plans/1-establish-nihongo-cli-foundations.md` through
`docs/plans/5-implement-kanji-show-command.md`). All five are checked in and
complete on `master`. Concretely you can rely on the following without reading
those plans, but the relevant files are named so a curious novice can verify.

The repository is a Cabal multi-package project. Two libraries:

- `nihongo-core` (path `nihongo-core/`, cabal file `nihongo-core/nihongo-core.cabal`)
  contains the pure-data, IO-light primitives.
- `nihongo-cli` (path `nihongo-cli/`, cabal file `nihongo-cli/nihongo-cli.cabal`)
  contains everything user-facing: argument parsing, terminal IO, the
  `nihongo` executable.

A single `cabal.project` at the root ties them together. The `nihongo`
executable is built from `nihongo-cli/app/Main.hs`, which calls
`Nihongo.Cli.runCli`. Both packages share a `common common-options` cabal
stanza that sets `default-language: GHC2024` and a long list of warning flags.

The pieces this plan composes are these three existing functions, in order of
the dataflow:

- `Nihongo.Kanji.KanjiVg.resolveKanjiVgRoot :: Maybe FilePath -> IO (Maybe KanjiVgRoot)`
  (file: `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`). Looks at, in order, the
  caller-supplied override, the `NIHONGO_KANJIVG_DIR` environment variable, and
  finally `<cwd>/data/kanjivg`. Returns the first one whose `kanji/`
  subdirectory exists. `KanjiVgRoot` is a single-field newtype around
  `FilePath`.

- `Nihongo.Kanji.KanjiVg.findStrokeSvg :: KanjiVgRoot -> Kanji -> IO (Maybe FilePath)`
  (same file). Computes the path `<root>/kanji/<5-hex-codepoint>.svg`,
  `doesFileExist`s it, and returns it (or `Nothing` if KanjiVG has no entry —
  the corpus does not cover every Unicode CJK codepoint).

- `Nihongo.Terminal.Image.ensurePng :: FilePath -> IO (Either Text FilePath)`
  (file: `nihongo-cli/src/Nihongo/Terminal/Image.hs`). Reads the SVG bytes,
  hashes them with SHA-256, and either returns the path of an already-cached
  `<sha>.png` under `<XDG_CACHE_HOME or ~/.cache>/nihongo/strokes/`, or shells
  out to `rsvg-convert --format=png --output <pngPath> <svgPath>` to produce
  it. Returns `Left "rsvg-convert not found: ..."` (or a similar message) on
  failure. `ensurePng` is already exported from `Nihongo.Terminal.Image` —
  verify by reading the module header.

The `Kanji` type itself is `Nihongo.Kanji.Kanji`, a newtype around `Char`
(file: `nihongo-core/src/Nihongo/Kanji.hs`). Construct it with
`mkKanji :: Char -> Either KanjiError Kanji`; `KanjiError` has the single
constructor `KanjiOutOfRange Char`. Project it back with
`unKanji :: Kanji -> Char`.

The CLI command tree is rooted in `Nihongo.Cli.commandParser`
(`nihongo-cli/src/Nihongo/Cli.hs`). The `kanji` subcommand lives in
`Nihongo.Cli.Commands.Kanji.kanjiParser` (file:
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji.hs`), which currently has exactly
one branch:

    hsubparser
      ( command "show"
          ( info (KShow <$> Show.showParser)
              (progDesc "Display stroke order for a kanji")))

This plan adds a second branch, `command "png"`.

Stdin handling for "kanji from positional or pipe" is already factored out into
`Nihongo.Cli.Stdin.getTextInput :: Maybe Text -> IO (Maybe Text)`
(file: `nihongo-cli/src/Nihongo/Cli/Stdin.hs`). Reuse it verbatim; do not
re-implement piped-input detection.

The help-topic system (file: `nihongo-cli/src/Nihongo/Cli/Help.hs`) loads
markdown files from `nihongo-cli/help/*.md` at compile time via
`Data.FileEmbed.embedStringFile`. Adding a topic is a two-step change: drop
the markdown file in `nihongo-cli/help/`, then add a `HelpTopic` row to the
`helpTopics` list. Because `file-embed` does not trigger cabal rebuilds when
the embedded file changes, after editing a `help/*.md` you must `touch
nihongo-cli/src/Nihongo/Cli/Help.hs` (or `cabal clean`) to force a relink.

Definitions of terms used below:

- *KanjiVG*: an open-source SVG kanji corpus. Each glyph is one file named by
  its lowercase 5-hex-digit Unicode codepoint, e.g. `06f22.svg` for 漢
  (U+6F22). The corpus lives at `data/kanjivg/` as a git submodule pinned to
  release `r20250816` by EP-2.

- *cache*: in this plan, the directory
  `<XDG_CACHE_HOME or ~/.cache>/nihongo/strokes/`, populated by `ensurePng`.
  Contents are PNG files named `<64-hex-sha256>.png`. Created on demand with
  `createDirectoryIfMissing True`, so calling code does not have to think
  about it.

- *XDG cache home*: per the XDG Base Directory specification, the user's
  per-user cache root is `$XDG_CACHE_HOME` if set, otherwise `~/.cache`.

- *option group*: a labelled section in `--help` output produced by wrapping a
  parser in `Options.Applicative.parserOptionGroup "Header" innerParser`.
  Cosmetic only.


## Plan of Work

Four milestones. Each is independently verifiable: A produces a callable
function (provable from `cabal repl`), B produces a callable subcommand
(provable from the shell), C makes `nihongo help` discover the new topic, and
D is the integration check.

There is no new package to add. No new cabal dependency is needed; everything
the new code touches is already in the existing build-depends sets of
`nihongo-cli` and `nihongo-core`.


### Milestone A — `Nihongo.Kanji.Png` library module

After this milestone a new module `Nihongo.Kanji.Png` lives in `nihongo-cli`
(at `nihongo-cli/src/Nihongo/Kanji/Png.hs`) and exports the typed function
`kanjiPngPath`, the option record `KanjiPngOptions`, and the error sum
`KanjiPngError`. No CLI plumbing yet.

Create the file `nihongo-cli/src/Nihongo/Kanji/Png.hs` with these contents.
Use this as a starting point; adjust import details only if the compiler
complains about something specific, and document any deviation in *Surprises &
Discoveries*:

    -- | Resolve a 'Kanji' to the absolute filesystem path of a cached PNG
    --   rendered from its KanjiVG SVG. Composes the existing KanjiVG lookup
    --   ('Nihongo.Kanji.KanjiVg.resolveKanjiVgRoot' /
    --   'Nihongo.Kanji.KanjiVg.findStrokeSvg') with the SVG → PNG cache
    --   ('Nihongo.Terminal.Image.ensurePng'). The PNG cache is shared with the
    --   inline-image renderer used by @nihongo kanji show@, so consumers
    --   benefit from cross-command cache hits.
    module Nihongo.Kanji.Png
      ( KanjiPngOptions (..)
      , defaultKanjiPngOptions
      , KanjiPngError (..)
      , renderKanjiPngError
      , kanjiPngPath
      ) where

    import Data.Text qualified as Text

    import Nihongo.Kanji (Kanji, unKanji)
    import Nihongo.Kanji.KanjiVg (findStrokeSvg, resolveKanjiVgRoot)
    import Nihongo.Prelude
    import Nihongo.Terminal.Image qualified as Image

    -- | Caller-supplied knobs. Currently just the same KanjiVG root override
    --   that 'resolveKanjiVgRoot' accepts; kept as a record so a future flag
    --   (e.g. cache-dir override) can be added without breaking call sites.
    newtype KanjiPngOptions = KanjiPngOptions
      { kanjivgDirOverride :: Maybe FilePath
      }
      deriving stock (Eq, Show)

    defaultKanjiPngOptions :: KanjiPngOptions
    defaultKanjiPngOptions = KanjiPngOptions { kanjivgDirOverride = Nothing }

    -- | Every way 'kanjiPngPath' can fail. Each constructor carries enough
    --   context to render a useful message without further IO.
    data KanjiPngError
      = -- | None of override / @NIHONGO_KANJIVG_DIR@ / @./data/kanjivg@ exists.
        KpeKanjiVgRootMissing
      | -- | KanjiVG has no @<5-hex>.svg@ for this kanji.
        KpeSvgMissing !Kanji
      | -- | @rsvg-convert@ failed (missing on PATH, exit non-zero, etc.). The
        --   payload is the message @ensurePng@ returned, verbatim.
        KpeRasterise !Text
      deriving stock (Eq, Show)

    -- | Format a 'KanjiPngError' into a single line of human-readable text
    --   suitable for stderr.
    renderKanjiPngError :: KanjiPngError -> Text
    renderKanjiPngError = \case
      KpeKanjiVgRootMissing ->
        "could not find the KanjiVG corpus; see `nihongo help kanji-png`"
      KpeSvgMissing k ->
        "KanjiVG has no entry for " <> Text.singleton (unKanji k)
      KpeRasterise msg ->
        "failed to rasterise SVG: " <> msg

    -- | Given a 'Kanji', return the absolute filesystem path to a cached PNG
    --   of its KanjiVG glyph. Rasterises on cache miss; second and subsequent
    --   calls for the same kanji are file-system cheap (a single
    --   'doesFileExist' check inside @ensurePng@).
    kanjiPngPath :: KanjiPngOptions -> Kanji -> IO (Either KanjiPngError FilePath)
    kanjiPngPath opts kanji = do
      mRoot <- resolveKanjiVgRoot (kanjivgDirOverride opts)
      case mRoot of
        Nothing -> pure (Left KpeKanjiVgRootMissing)
        Just root -> do
          mSvg <- findStrokeSvg root kanji
          case mSvg of
            Nothing -> pure (Left (KpeSvgMissing kanji))
            Just svgPath -> do
              ensured <- Image.ensurePng svgPath
              pure $ case ensured of
                Left err -> Left (KpeRasterise err)
                Right png -> Right png

Add `Nihongo.Kanji.Png` to the `exposed-modules` list of the `library` stanza
in `nihongo-cli/nihongo-cli.cabal`. Keep the list alphabetical
(`Nihongo.Kanji.Png` sorts between `Nihongo.Cli.Version`-and-friends and
`Nihongo.Pretty` — match the existing convention in the file rather than
inventing a new ordering).

Acceptance for Milestone A:

    cabal build all

succeeds with no warnings about the new module. Inside `cabal repl
nihongo-cli` you can:

    >>> import Nihongo.Kanji (mkKanji)
    >>> import Nihongo.Kanji.Png
    >>> Right k <- pure (mkKanji '漢')
    >>> kanjiPngPath defaultKanjiPngOptions k

and observe a `Right "/Users/.../strokes/<sha>.png"` (assuming the KanjiVG
submodule is initialised and `rsvg-convert` is on `PATH`). On a fresh cache
(`rm -rf ~/.cache/nihongo/strokes`) the first call rasterises; the second
call is a cache hit — verify by re-running and noting that no `rsvg-convert`
process is spawned (e.g. inspect with `ps -ef | grep rsvg` from another shell,
or simply observe that the wall time drops to milliseconds).


### Milestone B — `nihongo kanji png` subcommand

After this milestone the CLI exposes `nihongo kanji png <KANJI>`. It accepts a
positional kanji or piped stdin (matching `kanji show`), supports
`--kanjivg-dir PATH`, prints the PNG path to stdout on success, and writes a
human-readable error to stderr with exit 1 on failure.

Create `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Png.hs`. Mirror the shape of
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs` (already in the repo) so
that anyone reading the two files side-by-side can match the patterns:

    -- | The user-facing @nihongo kanji png <KANJI>@ subcommand. Resolves a
    --   single kanji (positional argument or stdin) to the absolute path of a
    --   cached PNG of its KanjiVG glyph and prints that path on stdout.
    --   Designed to be safe in shell substitution: stdout carries only the
    --   path on success, and is left empty on any error.
    module Nihongo.Cli.Commands.Kanji.Png
      ( PngCommand (..)
      , pngParser
      , runPng
      ) where

    import Data.Text qualified as Text
    import Data.Text.IO qualified as TIO
    import Options.Applicative
      ( Parser
      , argument
      , help
      , long
      , metavar
      , optional
      , parserOptionGroup
      , str
      , strOption
      )
    import System.Exit (exitFailure)
    import System.IO qualified as IO

    import Nihongo.Cli.Stdin qualified as Stdin
    import Nihongo.Kanji (Kanji, KanjiError (..), mkKanji)
    import Nihongo.Kanji.Png
      ( KanjiPngOptions (..)
      , kanjiPngPath
      , renderKanjiPngError
      )
    import Nihongo.Prelude

    data PngCommand = PngCommand
      { pngInput :: !(Maybe Text)
      , pngKanjivgDir :: !(Maybe FilePath)
      }
      deriving stock (Show, Eq)

    pngParser :: Parser PngCommand
    pngParser =
      PngCommand
        <$> optional
          ( argument
              str
              ( metavar "KANJI"
                  <> help "A single Japanese character. Reads from stdin if omitted."
              )
          )
        <*> parserOptionGroup "Source options" sourceGroup
      where
        sourceGroup =
          optional
            ( strOption
                ( long "kanjivg-dir"
                    <> metavar "PATH"
                    <> help "Override the KanjiVG checkout directory."
                )
            )

    runPng :: PngCommand -> IO ()
    runPng (PngCommand inputArg dirOverride) = do
      mInput <- Stdin.getTextInput inputArg
      kanji <- case mInput of
        Nothing -> die "expected a kanji as a positional argument or on stdin"
        Just t -> readSingleKanji t
      result <- kanjiPngPath (KanjiPngOptions dirOverride) kanji
      case result of
        Left err -> die (renderKanjiPngError err)
        Right path -> TIO.putStrLn (Text.pack path)

    readSingleKanji :: Text -> IO Kanji
    readSingleKanji raw =
      case Text.uncons (Text.strip raw) of
        Nothing -> die "expected a single character"
        Just (c, rest)
          | not (Text.null rest) -> die "expected a single character (got more)"
          | otherwise ->
              case mkKanji c of
                Left (KanjiOutOfRange ch) ->
                  die ("not a Japanese character: " <> Text.singleton ch)
                Right k -> pure k

    die :: Text -> IO a
    die msg = do
      TIO.hPutStrLn IO.stderr msg
      exitFailure

The `readSingleKanji` and `die` helpers are duplicated from
`Nihongo.Cli.Commands.Kanji.Show`. Do not refactor them into a shared module
in this plan — the duplication is six lines, the two callers may diverge
(e.g. `kanji show` may someday accept a multi-character word), and a
premature shared module would invite over-coupling. If a third sibling
command (e.g. `kanji components`) needs the same helpers, that is the right
moment to extract.

Add `Nihongo.Cli.Commands.Kanji.Png` to the `exposed-modules` list of
`nihongo-cli/nihongo-cli.cabal`'s `library` stanza, immediately after
`Nihongo.Cli.Commands.Kanji.Show`.

Edit `nihongo-cli/src/Nihongo/Cli/Commands/Kanji.hs` to wire the new
subcommand in. The diff is small and additive:

1. Add the import:

        import Nihongo.Cli.Commands.Kanji.Png qualified as Png

2. Extend the `KanjiCommand` ADT:

        data KanjiCommand
          = KShow !Show.ShowCommand
          | KPng !Png.PngCommand
          deriving stock (Show, Eq)

3. Add a second `command` block to `kanjiParser`:

        kanjiParser :: Parser KanjiCommand
        kanjiParser =
          hsubparser
            ( command
                "show"
                ( info
                    (KShow <$> Show.showParser)
                    (progDesc "Display stroke order for a kanji")
                )
                <> command
                  "png"
                  ( info
                      (KPng <$> Png.pngParser)
                      (progDesc "Print the path to a cached PNG of a kanji's stroke order")
                  )
            )

4. Add the new `runKanji` arm:

        runKanji (KPng c) = Png.runPng c

Do not modify `nihongo-cli/src/Nihongo/Cli.hs`; the new subcommand is already
reachable through the existing `command "kanji"` block.

Acceptance for Milestone B:

    cabal build all
    cabal run nihongo -- kanji --help

Output should now list both `show` and `png` under "Available commands".

    cabal run nihongo -- kanji png 漢

Should print a single absolute path like
`/Users/.../strokes/<sha>.png` to stdout and exit zero (verify via `echo $?`
in zsh, or wrap as `cabal run nihongo -- kanji png 漢 && echo OK`).

    file "$(cabal run -v0 nihongo -- kanji png 漢)"

Should report the file as a PNG image. (`-v0` is required to suppress cabal's
own informational lines so the substitution gets only the path.)

    echo 漢 | cabal run -v0 nihongo -- kanji png

Should produce the same path as the positional form.

    cabal run nihongo -- kanji png A
    cabal run nihongo -- kanji png 漢字

Each should exit non-zero with a stderr message (`not a Japanese character: A`
and `expected a single character (got more)`, respectively). Stdout must be
empty in both cases.


### Milestone C — Help topic

After this milestone `nihongo help` lists `kanji-png`, and `nihongo help
kanji-png` prints the topic body wrapped to terminal width.

Create `nihongo-cli/help/kanji-png.md` with this content (no fenced code
blocks; the help renderer is a plain text wrapper):

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

      ![漢](/$(nihongo kanji png 漢))

    ## Requirements

    - The KanjiVG submodule must be initialised:
      `git submodule update --init data/kanjivg`.
    - The system tool `rsvg-convert` (from `librsvg`) must be on `PATH`.
      The Nix devshell provides it via `pkgs.librsvg`.

Edit `nihongo-cli/src/Nihongo/Cli/Help.hs` to add a row to the `helpTopics`
list. The list is alphabetical by topic name; insert between `kanji-show`
and `width-demo`:

    helpTopics =
      [ HelpTopic "about"      "Project overview" $(embedStringFile "help/about.md")
      , HelpTopic "kanji-png"  "kanji png command reference" $(embedStringFile "help/kanji-png.md")
      , HelpTopic "kanji-show" "kanji show command reference" $(embedStringFile "help/kanji-show.md")
      , HelpTopic "width-demo" "Width-handling fixture topic" $(embedStringFile "help/width-demo.md")
      ]

Because `Data.FileEmbed.embedStringFile` does not trigger cabal rebuilds when
the embedded markdown file changes, the first build after creating the
markdown picks it up automatically (the import of `Nihongo.Cli.Help` itself
changed); subsequent edits to `help/kanji-png.md` will require either a
`touch nihongo-cli/src/Nihongo/Cli/Help.hs` or a `cabal clean && cabal build
all`. Document this only if the user encounters a stale topic body during
verification — Help.hs's module header already calls it out.

Acceptance for Milestone C:

    cabal build all
    cabal run nihongo -- help

Should list `kanji-png  -- kanji png command reference` among the topics
(between `about` and `kanji-show`).

    cabal run nihongo -- help kanji-png

Should print the topic body wrapped to the terminal width.


### Milestone D — End-to-end manual verification

After this milestone the user-visible feature is complete and verified. Run
every invocation in *Validation and Acceptance* and observe the documented
output. If any deviates, debug it before declaring the plan complete and
record what you found in *Surprises & Discoveries*.


## Concrete Steps

Run from the repository root (`/Users/shinzui/Keikaku/bokuno/nihongo`).

Milestone A — library function:

    # Create nihongo-cli/src/Nihongo/Kanji/Png.hs (see Plan of Work, Milestone A).
    # Add `Nihongo.Kanji.Png` to nihongo-cli/nihongo-cli.cabal exposed-modules.
    cabal build all
    # In a Kitty/WezTerm/Ghostty (or any terminal — this milestone does not render):
    cabal repl nihongo-cli
    # >>> import Nihongo.Kanji (mkKanji)
    # >>> import Nihongo.Kanji.Png
    # >>> Right k <- pure (mkKanji '漢')
    # >>> kanjiPngPath defaultKanjiPngOptions k

Milestone B — subcommand:

    # Create nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Png.hs.
    # Edit nihongo-cli/src/Nihongo/Cli/Commands/Kanji.hs (4 edits, see Plan).
    # Add Nihongo.Cli.Commands.Kanji.Png to nihongo-cli/nihongo-cli.cabal.
    cabal build all
    cabal run nihongo -- kanji --help
    cabal run nihongo -- kanji png 漢
    file "$(cabal run -v0 nihongo -- kanji png 漢)"

Milestone C — help topic:

    # Create nihongo-cli/help/kanji-png.md.
    # Edit nihongo-cli/src/Nihongo/Cli/Help.hs (one new HelpTopic row).
    cabal build all
    cabal run nihongo -- help
    cabal run nihongo -- help kanji-png

Milestone D — verification:

    cabal run nihongo -- kanji png 漢
    echo 漢 | cabal run -v0 nihongo -- kanji png
    cabal run nihongo -- kanji png 一
    cabal run nihongo -- kanji png A           # expect rejection on stderr
    cabal run nihongo -- kanji png 漢字         # expect rejection on stderr
    cabal run nihongo -- kanji png 漢 --kanjivg-dir data/kanjivg
    file "$(cabal run -v0 nihongo -- kanji png 漢)"
    cat "$(cabal run -v0 nihongo -- kanji png 漢)" | file -

When committing each milestone, every commit message must end with a blank
line followed by these two trailers:

    ExecPlan: docs/plans/7-add-kanji-png-subcommand-and-library-function-returning-a-cached-png-path-for-a-kanji.md
    Intention: intention_01kqxhfvpae3xv0dr9bnsxfdxs

Use a Conventional Commit subject like `feat(cli): EP-7 Milestone A — add
Nihongo.Kanji.Png library module` for milestone-bounded commits.


## Validation and Acceptance

The following invocations all run from the repo root with a working KanjiVG
submodule (`git submodule update --init data/kanjivg`) and `rsvg-convert` on
`PATH` (provided by `nix develop`).

`cabal run nihongo -- kanji png 漢` prints exactly one line of output to
stdout — an absolute filesystem path matching the regex
`^/.*/nihongo/strokes/[0-9a-f]{64}\.png$` — and exits 0.

`echo 漢 | cabal run -v0 nihongo -- kanji png` prints the same path as the
positional form (the cache key is the SVG bytes, which are identical for the
same kanji).

`cabal run -v0 nihongo -- kanji png 漢 | xargs file` reports the path as a
PNG image of dimensions 109 × 109.

`cabal run nihongo -- kanji png 一` prints a path to a different
`<sha>.png` file, also a valid PNG, and exits 0.

`cabal run nihongo -- kanji png A` writes `not a Japanese character: A` to
stderr, leaves stdout empty, and exits 1.

`cabal run nihongo -- kanji png 漢字` writes `expected a single character
(got more)` to stderr, leaves stdout empty, and exits 1.

`cabal run nihongo -- kanji png 漢 --kanjivg-dir data/kanjivg` produces the
same output as the no-flag form (it just makes the resolution explicit).

`cabal run nihongo -- kanji png 𠀋 --kanjivg-dir data/kanjivg` (a CJK
codepoint outside KanjiVG's coverage) writes
`KanjiVG has no entry for 𠀋` to stderr, leaves stdout empty, exits 1.

`NIHONGO_KANJIVG_DIR=/nonexistent cabal run nihongo -- kanji png 漢
--kanjivg-dir /also/nonexistent` writes `could not find the KanjiVG corpus;
see ` `nihongo help kanji-png` ` ` to stderr, leaves stdout empty, exits 1.

`PATH=/usr/bin cabal run nihongo -- kanji png 漢` (stripping the Nix shell so
`rsvg-convert` is unavailable, *and* with a fresh cache so the second-call
fast path is not taken — `rm -rf ~/.cache/nihongo/strokes/` first) writes
`failed to rasterise SVG: rsvg-convert not found: ...` to stderr, leaves
stdout empty, exits 1. (If the same kanji is already cached, `ensurePng`
returns early and the command succeeds — that is correct behaviour and not a
bug.)

`cabal run nihongo -- help kanji-png` prints the topic body, wrapped to the
terminal width.

`cabal run nihongo -- help` lists `kanji-png` between `about` and
`kanji-show`.

`cabal run nihongo -- kanji --help` lists both `show` and `png` under
"Available commands".

`cabal run nihongo -- kanji png --help` lists `--kanjivg-dir` under "Source
options".

`cabal run nihongo -- kanji show 漢` (the unrelated existing command) still
works exactly as before, and the cache hit shared between the two commands
makes the second invocation instantaneous (verify with
`time cabal run -v0 nihongo -- kanji show 漢` — wall time should be
single-digit milliseconds for the cache lookup).


## Idempotence and Recovery

Every step in this plan is idempotent. The library function is a thin wrapper
over three idempotent IO actions:

- `resolveKanjiVgRoot` is read-only.
- `findStrokeSvg` is read-only.
- `ensurePng` is the cache-check-or-write idiom from EP-4: a hit returns the
  same path; a miss writes the PNG once and any subsequent call hits.

Re-running `cabal run nihongo -- kanji png 漢` any number of times produces
identical stdout. There is no shared mutable state to corrupt.

To force a re-rasterisation, `rm <path-printed-by-the-command>`; the next
invocation will recreate it. To wipe the cache entirely,
`rm -rf ~/.cache/nihongo/strokes/`; it is recreated on demand by `cacheDir`
inside `Nihongo.Terminal.Image`.

If the markdown help file is edited in Milestone C and the help topic shows
stale content, that is the documented `file-embed` quirk — `touch
nihongo-cli/src/Nihongo/Cli/Help.hs` and rebuild.

If a partial edit leaves the build broken between milestones (e.g. cabal
file lists a module whose source you have not created yet), `git restore` or
remove the offending entry — there is no irreversible state to recover from.


## Interfaces and Dependencies

Cabal dependencies added: **none**. The new code uses only modules already
reachable through the existing `nihongo-cli` and `nihongo-core`
`build-depends` sets:

- `text` — for `Text`, `Text.uncons`, etc.
- `optparse-applicative` — for the new `pngParser`.
- `nihongo-core` — for `Kanji`, `mkKanji`, `unKanji`, `KanjiError`,
  `resolveKanjiVgRoot`, `findStrokeSvg`.
- `nihongo-cli`'s own `Nihongo.Terminal.Image` (for `ensurePng`),
  `Nihongo.Cli.Stdin` (for `getTextInput`), `Nihongo.Prelude`.

System tools required (provided by `flake.nix`): `rsvg-convert` from
`librsvg`. Already required by EP-4; this plan adds no new requirement.

Exposed modules added to `nihongo-cli/nihongo-cli.cabal`'s `library` stanza:

- `Nihongo.Kanji.Png`
- `Nihongo.Cli.Commands.Kanji.Png`

Module signatures introduced by this plan (post-Milestone A):

    module Nihongo.Kanji.Png where

      newtype KanjiPngOptions = KanjiPngOptions
        { kanjivgDirOverride :: Maybe FilePath }

      defaultKanjiPngOptions :: KanjiPngOptions

      data KanjiPngError
        = KpeKanjiVgRootMissing
        | KpeSvgMissing Kanji
        | KpeRasterise Text

      renderKanjiPngError :: KanjiPngError -> Text

      kanjiPngPath
        :: KanjiPngOptions
        -> Nihongo.Kanji.Kanji
        -> IO (Either KanjiPngError FilePath)

Module signatures introduced post-Milestone B:

    module Nihongo.Cli.Commands.Kanji.Png where

      data PngCommand = PngCommand
        { pngInput      :: Maybe Text
        , pngKanjivgDir :: Maybe FilePath
        }

      pngParser :: Options.Applicative.Parser PngCommand
      runPng    :: PngCommand -> IO ()

Files added by this plan:

    nihongo-cli/src/Nihongo/Kanji/Png.hs
    nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Png.hs
    nihongo-cli/help/kanji-png.md

Files modified by this plan:

    nihongo-cli/nihongo-cli.cabal               # +2 exposed-modules entries
    nihongo-cli/src/Nihongo/Cli/Commands/Kanji.hs  # KPng constructor + parser branch + run arm
    nihongo-cli/src/Nihongo/Cli/Help.hs          # +1 HelpTopic row

Files deleted by this plan: none.

Public APIs that downstream plans may rely on:

- `Nihongo.Kanji.Png.kanjiPngPath` — the canonical "give me a PNG for this
  kanji" function. Future commands (`kanji export`, an MCP server, etc.)
  should call this rather than re-composing `findStrokeSvg` and `ensurePng`
  themselves.
- `Nihongo.Kanji.Png.KanjiPngError` — extend with new constructors as new
  failure modes appear; existing callers using `renderKanjiPngError` will
  continue to compile and produce correct messages.
