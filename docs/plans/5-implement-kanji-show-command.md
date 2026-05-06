---
id: 5
slug: implement-kanji-show-command
title: "Implement kanji show command"
kind: exec-plan
created_at: 2026-05-06T02:27:21Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
master_plan: "docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md"
---

# Implement kanji show command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan a user can type a kanji and see its stroke order. This is the
end-state the master plan
`docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md` was created to
deliver.

Concretely:

    cabal run nihongo -- kanji show 漢

prints, in this order, on stdout:

1. A header line "漢 (U+6F22, 13 strokes)".
2. A blank line.
3. A numbered, narrated stroke order, one stroke per line:

        1. ㇔ dot
        2. ㇔ dot
        3. ㇀ rising
        4. ㇐ horizontal
        5. ㇑ vertical
        6. ㇑ vertical
        7. ㇑ vertical
        8. ㇕ turn-down
        9. ㇐ horizontal
        10. ㇐ horizontal
        11. ㇐ horizontal
        12. ㇒ left-falling
        13. ㇏ right-falling

4. A blank line.
5. (In a Kitty-graphics-capable terminal) an inline image of 漢 about 12 rows tall.
   (Otherwise: a dim line `[Image: 漢]`.)

The kanji can also be piped: `echo 漢 | nihongo kanji show` produces the same output.
The user can pass `--no-images` to suppress the image, `--format text` to print only
the text breakdown, `--format image` to skip the text, or `--kanjivg-dir PATH` to
override the SVG source. A new help topic `nihongo help kanji-show` describes the
command.

You will know it works when the four invocations in Validation and Acceptance
produce the documented outputs.

This plan deletes the temporary debug subcommands left behind by EP-2
(`kanji-debug-path`) and EP-4 (`image-debug-render`); their behaviour is now
subsumed by `kanji show`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone A: Create `Nihongo.Cli.Commands.Kanji.Show` with the parser, types, and runner.
- [ ] Milestone B: Add the `kanji` subcommand group to `Nihongo.Cli`.
- [ ] Milestone C: Add the `help/kanji-show.md` topic and register it in `helpTopics`.
- [ ] Milestone D: Delete the temporary debug subcommands (`kanji-debug-path`, `image-debug-render`).
- [ ] Milestone E: Manual verification of all five invocation forms in Validation and Acceptance.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Default `--format` to `both`.
  Rationale: Most users will run inside a Kitty-capable terminal and benefit from the
  combined output. Users who pipe (and therefore probably do not have an interactive
  terminal) get the same text portion regardless because the image rendering
  short-circuits to the placeholder when stdout is not a TTY-capable terminal.
  Date: 2026-05-05.

- Decision: Display the image *after* the text, not before.
  Rationale: The text portion is short and scrollable; the image consumes 12 rows
  and pushes earlier output up. Putting text first means the user always sees the
  numbered list close to the prompt; the image renders at the bottom. (`kizamu`
  uses the same convention.)
  Date: 2026-05-05.

- Decision: Use the option groups pattern (`parserOptionGroup`) introduced as
  available in EP-1: an "Output" group (`--format`), an "Image" group (`--no-images`),
  a "Source" group (`--kanjivg-dir`).
  Rationale: `kanji show` already has four flags; grouping makes `--help` legible.
  Date: 2026-05-05.

- Decision: Delete the temporary debug subcommands `kanji-debug-path` (introduced by
  EP-2) and `image-debug-render` (introduced by EP-4).
  Rationale: Both were explicitly scoped as temporary. `kanji show` exercises the
  same code paths and supersedes both. Keeping them around clutters `--help` and
  `--internal-help`.
  Date: 2026-05-05.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan assumes EP-1, EP-2, EP-3, and EP-4 are all complete. It depends on
artifacts from each of them. The relevant facts (so a novice does not have to
re-read the upstream plans):

From EP-1 (`docs/plans/1-establish-nihongo-cli-foundations.md`):

- `Nihongo.Prelude` re-exports `Text`, `Generic`, `MonadIO`, `liftIO`, `UTCTime`,
  `getCurrentTime`, `FromJSON`, `ToJSON`, `NonEmpty`, plus the lens / generic-lens
  vocabulary. `import Nihongo.Prelude` and you have all of those.
- `Nihongo.Pretty` exports `dim`, `bold`, `colored`, and `Color`.
- `Nihongo.Cli.Stdin.getTextInput :: Maybe Text -> IO (Maybe Text)` returns the user's
  positional argument if any, otherwise the trimmed contents of stdin if piped,
  otherwise `Nothing`.
- `Nihongo.Cli.Width.resolveWidth :: Maybe Int -> IO (Maybe Int)` and `wrapText :: Int
  -> Text -> Text`.
- `Nihongo.Cli.Help.HelpTopic { topicName, topicDescription, topicContent }` and the
  list `helpTopics` are loaded with `file-embed` from `nihongo-cli/help/`.
- The top-level parser in `Nihongo.Cli` already wires in `version`, `help`,
  `completions`, and (placeholder) `hello`.
- `optparse-applicative >= 0.19` is available, exposing `parserOptionGroup`.

From EP-2 (`docs/plans/2-add-kanjivg-submodule-and-lookup.md`):

- The KanjiVG corpus is at `data/kanjivg/` (a git submodule pinned to `r20250816`).
- `Nihongo.Kanji.Kanji` is a newtype over `Char`. `mkKanji :: Char -> Either
  KanjiError Kanji` is the smart constructor; `KanjiError` has constructor
  `KanjiOutOfRange Char`.
- `Nihongo.Kanji.kanjiCodepointHex :: Kanji -> Text` produces e.g. `"06f22"`.
- `Nihongo.Kanji.unKanji :: Kanji -> Char`.
- `Nihongo.Kanji.KanjiVg.KanjiVgRoot` is the resolved root directory.
- `Nihongo.Kanji.KanjiVg.resolveKanjiVgRoot :: Maybe FilePath -> IO (Maybe KanjiVgRoot)`
  obeys the priority `--kanjivg-dir` > `NIHONGO_KANJIVG_DIR` env var > `<cwd>/data/kanjivg`.
- `Nihongo.Kanji.KanjiVg.findStrokeSvg :: KanjiVgRoot -> Kanji -> IO (Maybe FilePath)`
  returns the absolute SVG path (or `Nothing` if KanjiVG has no entry).

From EP-3 (`docs/plans/3-parse-kanjivg-stroke-order-metadata.md`):

- `Nihongo.Kanji.StrokeOrder.parseStrokeOrderFile :: FilePath -> IO (Either ParseError
  StrokeOrderInfo)`.
- `StrokeOrderInfo { strokes :: [Stroke], componentTree :: ComponentTree }`.
- `Stroke { strokeIndex :: Int, strokeRawType :: Maybe Text, strokeType :: Maybe
  StrokeType, strokePathD :: Text }`.
- `Nihongo.Kanji.StrokeType.StrokeType { baseChar :: Char, variant :: Maybe Text }`.
- `Nihongo.Kanji.StrokeType.describeStrokeType :: StrokeType -> Maybe Text` (e.g.
  `"horizontal"`, `"vertical"`, `"left-falling"`).

From EP-4 (`docs/plans/4-render-images-in-the-terminal-via-kitty-graphics.md`):

- `Nihongo.Terminal.Image.ImageCapability` (`KittyGraphics | NoImageSupport`).
- `Nihongo.Terminal.Image.detectImageCapabilityWithOverride :: Bool -> IO ImageCapability`
  (the `Bool` means "force NoImageSupport").
- `Nihongo.Terminal.Image.displaySvg :: ImageCapability -> Text -> FilePath -> IO ()`
  prints either the inline image (under `KittyGraphics`) or a dim placeholder
  (`[Image: <label>]`) under `NoImageSupport`.

From the existing repository (committed before any of these plans began):

- `nihongo-core` and `nihongo-cli` are two cabal packages in a single project.
- Both share a `common common-options` cabal stanza with `default-language: GHC2024`
  and the same default extensions and warnings.

Definitions of terms used below:

- *option group*: a labelled sub-section in `--help` output. Created by wrapping a
  parser in `parserOptionGroup "Header" innerParser`. Pure cosmetic; no runtime
  effect.
- *positional argument*: a flag-less argument like `kanji show 漢` (where 漢 is
  positional). Optparse-applicative parses these with `argument`.


## Plan of Work

Five milestones. Implement in order; do not skip ahead.


### Milestone A — `Nihongo.Cli.Commands.Kanji.Show`

After this milestone the module is implemented but not yet wired into the top-level
parser.

Create `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`:

    module Nihongo.Cli.Commands.Kanji.Show
      ( ShowCommand (..)
      , OutputFormat (..)
      , showParser
      , runShow
      ) where

    import qualified Data.Text as Text
    import qualified Data.Text.IO as TIO
    import Numeric (showHex)
    import Options.Applicative
        ( Parser
        , argument
        , help
        , long
        , maybeReader
        , metavar
        , option
        , optional
        , parserOptionGroup
        , str
        , strOption
        , switch
        , value
        , showDefault
        )
    import qualified System.IO as IO
    import System.Exit (exitFailure)

    import Nihongo.Kanji (Kanji, KanjiError (..), kanjiCodepointHex, mkKanji, unKanji)
    import Nihongo.Kanji.KanjiVg (findStrokeSvg, resolveKanjiVgRoot)
    import Nihongo.Kanji.StrokeOrder
        ( ParseError
        , Stroke (..)
        , StrokeOrderInfo (..)
        , parseStrokeOrderFile
        )
    import Nihongo.Kanji.StrokeType (StrokeType (..), describeStrokeType)
    import qualified Nihongo.Cli.Stdin as Stdin
    import qualified Nihongo.Pretty as Pretty
    import qualified Nihongo.Terminal.Image as Image
    import Nihongo.Prelude

    data OutputFormat = FormatText | FormatImage | FormatBoth
      deriving stock (Eq, Show)

    data ShowCommand = ShowCommand
      { showInput        :: Maybe Text
      , showFormat       :: OutputFormat
      , showNoImages     :: Bool
      , showKanjivgDir   :: Maybe FilePath
      }
      deriving stock (Show, Eq)

    showParser :: Parser ShowCommand
    showParser =
      ShowCommand
        <$> optional (argument str
              (metavar "KANJI"
            <> help "A single Japanese character. Reads from stdin if omitted."))
        <*> parserOptionGroup "Output options" outputGroup
        <*> parserOptionGroup "Image options"  imageGroup
        <*> parserOptionGroup "Source options" sourceGroup
      where
        outputGroup =
          option (maybeReader parseFormat)
            ( long "format"
           <> metavar "FORMAT"
           <> value FormatBoth
           <> showDefault
           <> help "Output to print: text | image | both" )

        imageGroup =
          switch
            ( long "no-images"
           <> help "Do not render the inline kanji image, even when supported." )

        sourceGroup =
          optional (strOption
            ( long "kanjivg-dir"
           <> metavar "PATH"
           <> help "Override the KanjiVG checkout directory." ))

        parseFormat "text"  = Just FormatText
        parseFormat "image" = Just FormatImage
        parseFormat "both"  = Just FormatBoth
        parseFormat _       = Nothing

    runShow :: ShowCommand -> IO ()
    runShow (ShowCommand inputArg fmt noImages dirOverride) = do
      mInput <- Stdin.getTextInput inputArg
      kanji  <- case mInput of
        Nothing -> die "expected a kanji as a positional argument or on stdin"
        Just t  -> readSingleKanji t
      mroot <- resolveKanjiVgRoot dirOverride
      root  <- case mroot of
        Nothing -> die "could not find the KanjiVG corpus; see `nihongo help kanji-show`"
        Just r  -> pure r
      mPath <- findStrokeSvg root kanji
      svg   <- case mPath of
        Nothing -> die ("KanjiVG has no entry for " <> Text.singleton (unKanji kanji))
        Just p  -> pure p
      result <- parseStrokeOrderFile svg
      info   <- case result of
        Left err   -> die ("failed to parse SVG: " <> Text.pack (show (err :: ParseError)))
        Right info -> pure info
      cap    <- Image.detectImageCapabilityWithOverride noImages
      printOutput fmt cap kanji info svg

    -- ----------------------------------------------------------------------
    -- helpers
    -- ----------------------------------------------------------------------

    readSingleKanji :: Text -> IO Kanji
    readSingleKanji raw =
      case Text.uncons (Text.strip raw) of
        Nothing -> die "expected a single character"
        Just (c, rest)
          | not (Text.null rest) -> die "expected a single character (got more)"
          | otherwise            ->
              case mkKanji c of
                Left (KanjiOutOfRange ch) ->
                  die ("not a Japanese character: " <> Text.singleton ch)
                Right k -> pure k

    printOutput :: OutputFormat -> Image.ImageCapability -> Kanji -> StrokeOrderInfo -> FilePath -> IO ()
    printOutput fmt cap kanji info svgPath = do
      case fmt of
        FormatImage -> pure ()
        _           -> do
          TIO.putStrLn (header kanji info)
          TIO.putStrLn ""
          mapM_ (TIO.putStrLn . renderStrokeLine) (strokes info)
          TIO.putStrLn ""
      case fmt of
        FormatText  -> pure ()
        _           -> Image.displaySvg cap (Text.singleton (unKanji kanji)) svgPath

    header :: Kanji -> StrokeOrderInfo -> Text
    header k info =
      let cp     = kanjiCodepointHex k
          uHex   = Text.toUpper (Text.dropWhile (== '0') cp)
          glyph  = Text.singleton (unKanji k)
          n      = length (strokes info)
       in Pretty.bold glyph
            <> " (U+" <> uHex <> ", " <> Text.pack (show n) <> " strokes)"

    renderStrokeLine :: Stroke -> Text
    renderStrokeLine s =
      let n   = Text.pack (show (strokeIndex s))
          rt  = maybe "" Text.singleton (baseChar <$> strokeType s)
          d   = maybe "" id (describeStrokeType =<< strokeType s)
          sep = if Text.null d then "" else " " <> d
       in n <> ". " <> rt <> sep

    die :: Text -> IO a
    die msg = do
      TIO.hPutStrLn IO.stderr msg
      exitFailure

Add `Nihongo.Cli.Commands.Kanji.Show` to `nihongo-cli/nihongo-cli.cabal`'s library
`exposed-modules`.

Acceptance: `cabal build all` succeeds. (No runtime check yet; Milestone B wires it
in.)

Note on `parserOptionGroup`: it lives in `Options.Applicative` from version 0.19;
EP-1 already bumped the bound. If your build resolves an older version (e.g. via a
stale `cabal.project.freeze`), update or drop the freeze file.


### Milestone B — Add the `kanji` subcommand group to `Nihongo.Cli`

After this milestone `nihongo kanji show <K>` is callable.

Create `nihongo-cli/src/Nihongo/Cli/Commands/Kanji.hs` to hold the `kanji` subcommand
group's dispatcher:

    module Nihongo.Cli.Commands.Kanji
      ( KanjiCommand (..)
      , kanjiParser
      , runKanji
      ) where

    import Options.Applicative
        ( Parser
        , command
        , hsubparser
        , info
        , progDesc
        )

    import qualified Nihongo.Cli.Commands.Kanji.Show as Show

    data KanjiCommand
      = KShow Show.ShowCommand
      deriving stock (Show, Eq)

    kanjiParser :: Parser KanjiCommand
    kanjiParser =
      hsubparser
        ( command "show" (info (KShow <$> Show.showParser)
            (progDesc "Display stroke order for a kanji"))
        )

    runKanji :: KanjiCommand -> IO ()
    runKanji (KShow c) = Show.runShow c

Add `Nihongo.Cli.Commands.Kanji` to `nihongo-cli/nihongo-cli.cabal`'s library
`exposed-modules`.

Edit `nihongo-cli/src/Nihongo/Cli.hs` to add the `kanji` subcommand. The exact
edits:

1. Add the import:

        import qualified Nihongo.Cli.Commands.Kanji as Kanji

2. Extend the `Command` ADT:

        data Command
          = CmdHello (Maybe Text)
          | CmdHelp Help.HelpCommand
          | CmdCompletions Completions.CompletionsShell
          | CmdKanji Kanji.KanjiCommand
          deriving stock (Show, Eq)

3. Add the new `command` block to `commandParser` (between `hello` and `help`,
   alphabetically, or wherever you prefer):

        <> command "kanji" (info (CmdKanji <$> Kanji.kanjiParser)
            (progDesc "Look up kanji: stroke order, components, readings"))

4. Add the dispatch arm to `runCommand`:

        runCommand (CmdKanji c) = Kanji.runKanji c

Acceptance: `cabal build all` succeeds. `cabal run nihongo -- --help` shows the
`kanji` subcommand under "Available commands". `cabal run nihongo -- kanji show 漢`
prints the documented output.


### Milestone C — Help topic

Create `nihongo-cli/help/kanji-show.md`:

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

Edit `nihongo-cli/src/Nihongo/Cli/Help.hs` to register the topic. The
`helpTopics` list grows by one entry:

    helpTopics =
      [ HelpTopic "about"      "Project overview" $(embedStringFile "help/about.md")
      , HelpTopic "kanji-show" "kanji show command reference" $(embedStringFile "help/kanji-show.md")
      , HelpTopic "width-demo" "Width-handling fixture topic" $(embedStringFile "help/width-demo.md")
      ]

Note: `file-embed` does not trigger cabal rebuilds when the underlying `.md` file
changes. After editing the markdown, `touch nihongo-cli/src/Nihongo/Cli/Help.hs` or
run `cabal clean && cabal build all` to force a rebuild.

Acceptance: `cabal run nihongo -- help` lists `kanji-show` among the topics.
`cabal run nihongo -- help kanji-show` prints the topic body.


### Milestone D — Remove the temporary debug subcommands

Delete `nihongo-cli/src/Nihongo/Cli/Commands/KanjiDebug.hs` (introduced by EP-2) and
`nihongo-cli/src/Nihongo/Cli/Commands/ImageDebug.hs` (introduced by EP-4). Remove
their entries from `nihongo-cli/nihongo-cli.cabal`'s `exposed-modules`. Remove their
imports, `Command` ADT constructors, `command "..."` blocks, and `runCommand` arms
from `nihongo-cli/src/Nihongo/Cli.hs`.

Acceptance: `cabal build all` succeeds. `cabal run nihongo -- kanji-debug-path 漢`
exits with "Invalid argument" / "no such command". Same for `image-debug-render`.


### Milestone E — End-to-end manual verification

After this milestone the user-visible feature is complete and verified.

Run each invocation listed in Validation and Acceptance and observe the documented
output. If any deviates, debug it before declaring the plan complete.


## Concrete Steps

Run from the repo root.

Milestone A:

    # Create nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs.
    # Add to exposed-modules.
    cabal build all

Milestone B:

    # Create nihongo-cli/src/Nihongo/Cli/Commands/Kanji.hs.
    # Edit nihongo-cli/src/Nihongo/Cli.hs.
    # Add Kanji and Kanji.Show to exposed-modules.
    cabal build all
    cabal run nihongo -- kanji show 漢

Milestone C:

    # Create nihongo-cli/help/kanji-show.md.
    # Edit nihongo-cli/src/Nihongo/Cli/Help.hs.
    cabal build all
    cabal run nihongo -- help kanji-show

Milestone D:

    rm nihongo-cli/src/Nihongo/Cli/Commands/KanjiDebug.hs
    rm nihongo-cli/src/Nihongo/Cli/Commands/ImageDebug.hs
    # Edit nihongo-cli.cabal and Nihongo.Cli to drop their references.
    cabal build all

Milestone E:

    cabal run nihongo -- kanji show 漢
    cabal run nihongo -- kanji show 漢 --no-images
    cabal run nihongo -- kanji show 漢 --format text
    cabal run nihongo -- kanji show 漢 --format image
    echo 漢 | cabal run nihongo -- kanji show
    cabal run nihongo -- kanji show A         # expect rejection
    cabal run nihongo -- kanji show 漢字       # expect rejection
    cabal run nihongo -- kanji show 一        # 1-stroke kanji


## Validation and Acceptance

Run inside a Kitty-graphics-capable terminal with the KanjiVG submodule initialised
(`git submodule update --init data/kanjivg`) and `rsvg-convert` on `PATH`.

`cabal run nihongo -- kanji show 漢` prints:

    漢 (U+6F22, 13 strokes)

    1. ㇔ dot
    2. ㇔ dot
    3. ㇀ rising
    4. ㇐ horizontal
    5. ㇑ vertical
    6. ㇑ vertical
    7. ㇑ vertical
    8. ㇕ turn-down
    9. ㇐ horizontal
    10. ㇐ horizontal
    11. ㇐ horizontal
    12. ㇒ left-falling
    13. ㇏ right-falling

    <inline image of 漢, ~12 rows tall>

(The header line "漢 (U+6F22, 13 strokes)" has the kanji bolded by `Pretty.bold`.
On terminals without ANSI bold support the kanji still appears, just not bolded.)

`cabal run nihongo -- kanji show 漢 --no-images` prints the same text plus a dim
placeholder `[Image: 漢]` instead of the inline image.

`cabal run nihongo -- kanji show 漢 --format text` prints only the header and the
13 stroke lines; no image, no placeholder.

`cabal run nihongo -- kanji show 漢 --format image` prints only the inline image
(or the placeholder); no header, no stroke lines.

`echo 漢 | cabal run nihongo -- kanji show` prints the same as the first invocation:
stdin satisfies the missing positional argument.

`cabal run nihongo -- kanji show A` exits non-zero, printing `not a Japanese
character: A` to stderr.

`cabal run nihongo -- kanji show 漢字` exits non-zero, printing `expected a single
character (got more)` to stderr.

`cabal run nihongo -- kanji show 一` prints `一 (U+4E00, 1 strokes)` followed by
`1. ㇐ horizontal` and the inline image.

`cabal run nihongo -- help kanji-show` prints the contents of
`nihongo-cli/help/kanji-show.md` wrapped to the terminal width.

`cabal run nihongo -- --help` shows the `kanji` subcommand. `cabal run nihongo --
kanji --help` shows the `show` subcommand. `cabal run nihongo -- kanji show --help`
shows the three option groups (Output options, Image options, Source options) each
with their flag.


## Idempotence and Recovery

Re-running the command on the same kanji is fast: EP-3's parser is pure (no caching
needed beyond the OS file cache), and EP-4's `ensurePng` cache hits the second time.

If the SVG is missing (`KanjiVG has no entry for 𠀋`), the command exits non-zero
with a clear message; no recovery action is needed beyond informing the user that
KanjiVG does not cover every Unicode CJK codepoint.

If `rsvg-convert` is missing on `PATH`, EP-4's `displaySvg` falls back to the
placeholder and prints a stderr warning; the text portion of `kanji show` still
works. Recovery: `nix develop` to enter the dev shell that provides `librsvg`.

If `data/kanjivg/` is empty (submodule not initialised), `resolveKanjiVgRoot`
returns `Nothing` and the command exits non-zero with the message documented in
EP-2's `defaultKanjiVgRoot`. Recovery: `git submodule update --init data/kanjivg`.


## Interfaces and Dependencies

Cabal dependencies added: none. All needed packages (`optparse-applicative`,
`text`, `nihongo-core`, etc.) are already present after EP-1 through EP-4.

Exposed modules added to `nihongo-cli/nihongo-cli.cabal`:

- `Nihongo.Cli.Commands.Kanji`
- `Nihongo.Cli.Commands.Kanji.Show`

Exposed modules removed:

- `Nihongo.Cli.Commands.KanjiDebug` (introduced by EP-2)
- `Nihongo.Cli.Commands.ImageDebug` (introduced by EP-4)

Public APIs this plan defines: none for downstream plans. The MasterPlan ends here;
future feature plans (e.g. `kanji find`, `vocab`) will define their own commands.

Files added by this plan:

    nihongo-cli/src/Nihongo/Cli/Commands/Kanji.hs
    nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs
    nihongo-cli/help/kanji-show.md

Files modified:

    nihongo-cli/nihongo-cli.cabal           # exposed-modules
    nihongo-cli/src/Nihongo/Cli.hs          # subcommand wiring
    nihongo-cli/src/Nihongo/Cli/Help.hs     # helpTopics list

Files deleted:

    nihongo-cli/src/Nihongo/Cli/Commands/KanjiDebug.hs
    nihongo-cli/src/Nihongo/Cli/Commands/ImageDebug.hs

System tools required (provided by `flake.nix` after EP-1):

- `rsvg-convert` from `librsvg` — only required when the user wants the inline
  image; the text portion of `kanji show` works without it.
