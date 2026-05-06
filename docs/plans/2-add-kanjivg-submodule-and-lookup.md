---
id: 2
slug: add-kanjivg-submodule-and-lookup
title: "Add KanjiVG submodule and lookup"
kind: exec-plan
created_at: 2026-05-06T02:27:16Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
master_plan: "docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md"
---

# Add KanjiVG submodule and lookup

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan, the `nihongo` repository carries the KanjiVG SVG corpus as a git
submodule at `data/kanjivg/`, and `nihongo-core` exposes a small library that can take
a Japanese character and return the absolute path to its KanjiVG SVG file on disk. A
developer at the `cabal repl` can run

    >>> import Nihongo.Kanji
    >>> import Nihongo.Kanji.KanjiVg
    >>> root <- defaultKanjiVgRoot
    >>> Right k <- pure (mkKanji '漢')
    >>> findStrokeSvg root k
    Just "/Users/.../nihongo/data/kanjivg/kanji/06f22.svg"

and confirm the path resolves to a real file. That is the foundation EP-3 (the SVG
parser) and EP-5 (the user-facing `kanji show` command) build on. Without this plan
they have nothing to read.

KanjiVG (https://github.com/KanjiVG/kanjivg) is a CC-BY-SA 3.0 corpus of Unicode CJK
glyphs as SVGs annotated with stroke-order metadata in the `kvg:` namespace. It
contains roughly 12,000 glyphs covering kanji, hiragana, katakana, and many CJK
radicals — all stored in a single flat directory `kanji/` regardless of script. Each
glyph file is named `<codepoint>.svg`, where `<codepoint>` is the Unicode codepoint
in lowercase hexadecimal padded to exactly 5 digits: 漢 (U+6F22) is `06f22.svg`,
仮 (U+4EEE) is `04eee.svg`, あ (U+3042) is `03042.svg`. A handful of variant files
exist with the form `<codepoint>-<Suffix>.svg` (for example `04e14-Kaisho.svg`); for
this plan we ignore variants and always fetch the unsuffixed primary file.

You will know it works when:

    git submodule status
    cabal run nihongo -- kanji-debug-path 漢
    cabal run nihongo -- kanji-debug-path あ
    cabal run nihongo -- kanji-debug-path A

prints, in order, a non-empty submodule status line; an absolute path ending in
`/data/kanjivg/kanji/06f22.svg`; an absolute path ending in
`/data/kanjivg/kanji/03042.svg`; and a friendly "not a Japanese character" error. The
`kanji-debug-path` command is a hidden temporary debug subcommand introduced in this
plan and removed by EP-5 once `kanji show` exists.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone A: Add the KanjiVG git submodule at `data/kanjivg/` pinned to `r20250816`. (2026-05-05)
- [x] Milestone A: Document submodule clone instructions in `README.md`. (2026-05-05)
- [ ] Milestone B: Implement `Nihongo.Kanji` (newtype + smart constructor + codepoint helpers).
- [ ] Milestone C: Implement `Nihongo.Kanji.KanjiVg` (root resolution + `findStrokeSvg`).
- [ ] Milestone D: Add the temporary `kanji-debug-path` subcommand to validate end-to-end and exercise root resolution.
- [ ] Milestone D: Manual verification of all three lookup cases (kanji, kana, non-Japanese).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **Tag `r20250816` resolves to commit `bd13ffbcc9d85cb86ae98bbbf001d9069220b901`,
  not `544d319f...`.** The plan's Decision Log mentioned `544d319f...`, but that
  is the user's standalone clone's `master` HEAD at the time of writing — *not*
  the commit the tag points at. Both clones agree the tag itself is `bd13ffbcc...`.
  Evidence: `git -C data/kanjivg rev-list -n 1 r20250816` and the same query
  against `/Users/shinzui/Keikaku/hub/kanjivg` both print `bd13ffbcc...`. EP-3
  and EP-5 should reference the tag (`r20250816`) rather than the commit hash;
  the tag is the stable identifier.


## Decision Log

Record every decision made while working on the plan.

- Decision: Pin the submodule to release tag `r20250816` rather than to `master` or a
  raw commit hash.
  Rationale: Tags are more legible to humans browsing the submodule history, and
  KanjiVG resets `master` every few months; a tag captures the "intended" snapshot
  while still being a fixed point. The tag `r20250816` is the latest at the time of
  writing (commit `544d319f79348c092d567b662f27f33dacfa60cd`).
  Date: 2026-05-05.

- Decision: The `Kanji` smart constructor accepts characters in the Unicode CJK
  Unified Ideographs range (U+4E00–U+9FFF), CJK Unified Ideographs Extension A
  (U+3400–U+4DBF), and the kana ranges (Hiragana U+3040–U+309F, Katakana
  U+30A0–U+30FF). Characters outside these ranges are rejected.
  Rationale: KanjiVG covers all of those, and rejecting ASCII / Latin / digits early
  gives the CLI a better error message than "file not found." Extension B (U+20000+)
  and the supplementary CJK blocks are excluded for v1; if a user reports needing
  them we relax the smart constructor.
  Date: 2026-05-05.

- Decision: Resolve the `KanjiVgRoot` in priority order — explicit `--kanjivg-dir`,
  then `NIHONGO_KANJIVG_DIR` env var, then `<cwd>/data/kanjivg`.
  Rationale: Power users can override (useful for testing alternate KanjiVG forks);
  CI can set the env var; everyone else just gets it for free from the submodule when
  they run from the project root. Hard-coding only would break installed binaries.
  Date: 2026-05-05.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan assumes EP-1 (`docs/plans/1-establish-nihongo-cli-foundations.md`) is
complete: `Nihongo.Prelude` is the expanded custom prelude, the shared cabal
`common-options` stanza supports `MultilineStrings`, and `flake.nix` provides
`gitMinimal`. Every module added in this plan starts with `import Nihongo.Prelude`.

The repository layout you can assume after EP-1:

    nihongo-core/
      nihongo-core.cabal
      src/Nihongo/Prelude.hs
    nihongo-cli/
      nihongo-cli.cabal
      app/Main.hs
      help/about.md, help/width-demo.md
      src/Nihongo/Cli.hs
      src/Nihongo/Cli/{Version,Stdin,Width,Help,Completions}.hs
      src/Nihongo/Pretty.hs
    cabal.project
    flake.nix
    .gitignore
    docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md
    docs/plans/1..5-*.md

The user already has a clean clone of KanjiVG at `/Users/shinzui/Keikaku/hub/kanjivg`
checked out at tag `r20250816` (commit `544d319f79348c092d567b662f27f33dacfa60cd`).
You will *not* re-clone from there; you will add a submodule from the upstream URL
`https://github.com/KanjiVG/kanjivg.git`, because submodules need to be reproducible
for any contributor cloning fresh.

Definitions of terms used below:

- *git submodule*: a pinned reference to another git repo. The pin is stored in two
  places — a `[submodule]` block in `.gitmodules` (committed), and a special tree
  entry in the parent repo (also committed). When someone clones the parent repo they
  must run `git submodule update --init` to materialize the submodule's working tree.
- *KanjiVG codepoint filename*: lowercase 5-digit hex of the Unicode codepoint, no
  prefix, padded with leading zeros. 漢 (U+6F22) → `06f22.svg`. There is no separate
  directory for kana; `kanji/` is flat.
- *kvg: namespace*: the `xmlns:kvg="http://kanjivg.tagaini.net/kanjivg.xsd"` namespace
  that decorates SVG elements with stroke-order metadata. EP-3 parses this; this plan
  only finds the file on disk.

Reference paths if you need to inspect the corpus directly:

    /Users/shinzui/Keikaku/hub/kanjivg/                # user's standalone clone
    /Users/shinzui/Keikaku/hub/kanjivg/kanji/06f22.svg # 漢
    /Users/shinzui/Keikaku/hub/kanjivg/kanji/03042.svg # あ


## Plan of Work

Four milestones.


### Milestone A — Add the submodule

After this milestone the parent repo carries the submodule pin and a fresh clone can
materialize it.

From the repo root:

    git submodule add https://github.com/KanjiVG/kanjivg.git data/kanjivg
    (cd data/kanjivg && git fetch --tags && git checkout r20250816)
    git add .gitmodules data/kanjivg
    # Commit; the master-plan/exec-plan trailers will be added per the skills.

Append a section to `README.md` immediately under "Develop":

    ## Data: KanjiVG submodule

    The KanjiVG SVG corpus (https://github.com/KanjiVG/kanjivg) is included as a git
    submodule at `data/kanjivg/`, pinned to release tag `r20250816`. After cloning
    the repository, run:

    ```bash
    git submodule update --init --depth 1 data/kanjivg
    ```

    KanjiVG is licensed under CC-BY-SA 3.0; the submodule keeps its license boundary
    distinct from this project. The corpus is roughly 78 MB; a `--depth 1` clone is
    plenty since we never read its history.

Acceptance: `git submodule status` prints one line whose suffix is `(r20250816)`. `ls
data/kanjivg/kanji/06f22.svg` succeeds.


### Milestone B — `Nihongo.Kanji` newtype and codepoint helpers

After this milestone `nihongo-core` exposes a `Kanji` newtype with a smart constructor
and a helper that turns a `Kanji` into the 5-digit hex codepoint string KanjiVG
expects.

Create `nihongo-core/src/Nihongo/Kanji.hs`:

    module Nihongo.Kanji
      ( Kanji
      , unKanji
      , mkKanji
      , kanjiCodepointHex
      , KanjiError (..)
      ) where

    import Data.Char (ord)
    import qualified Data.Text as Text
    import Numeric (showHex)

    import Nihongo.Prelude

    newtype Kanji = Kanji { unKanji :: Char }
      deriving stock (Eq, Show)

    data KanjiError
      = KanjiOutOfRange Char
      deriving stock (Eq, Show)

    -- | Smart constructor. Accepts characters in:
    --     * CJK Unified Ideographs        U+4E00 – U+9FFF
    --     * CJK Unified Ideographs Ext A  U+3400 – U+4DBF
    --     * Hiragana                      U+3040 – U+309F
    --     * Katakana                      U+30A0 – U+30FF
    --   Rejects anything else, including ASCII, digits, and CJK Ext B/C/D/E/F/G.
    mkKanji :: Char -> Either KanjiError Kanji
    mkKanji c
      | isInRange = Right (Kanji c)
      | otherwise = Left (KanjiOutOfRange c)
      where
        cp = ord c
        isInRange =
             (cp >= 0x4E00 && cp <= 0x9FFF)   -- CJK Unified Ideographs
          || (cp >= 0x3400 && cp <= 0x4DBF)   -- CJK Unified Ideographs Ext A
          || (cp >= 0x3040 && cp <= 0x309F)   -- Hiragana
          || (cp >= 0x30A0 && cp <= 0x30FF)   -- Katakana

    -- | Render a `Kanji` as the 5-digit lowercase hex codepoint KanjiVG uses
    --   for filenames. e.g. `kanjiCodepointHex (Kanji '漢') == "06f22"`.
    kanjiCodepointHex :: Kanji -> Text
    kanjiCodepointHex (Kanji c) =
      Text.pack (pad 5 (showHex (ord c) ""))
      where
        pad n s = replicate (n - length s) '0' <> s

Add `Nihongo.Kanji` to the `nihongo-core/nihongo-core.cabal` library `exposed-modules`
list (after `Nihongo.Prelude`).

Acceptance: `cabal build all` succeeds. In `cabal repl nihongo-core`:

    >>> import Nihongo.Kanji
    >>> kanjiCodepointHex <$> mkKanji '漢'
    Right "06f22"
    >>> mkKanji 'A'
    Left (KanjiOutOfRange 'A')


### Milestone C — `Nihongo.Kanji.KanjiVg` lookup

After this milestone `nihongo-core` exposes a function that resolves the KanjiVG root
directory and a function that maps `Kanji -> Maybe FilePath` for that root.

Add `directory ^>= 1.3` and `filepath ^>= 1.4` to `nihongo-core/nihongo-core.cabal`'s
library `build-depends`.

Create `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`:

    module Nihongo.Kanji.KanjiVg
      ( KanjiVgRoot (..)
      , defaultKanjiVgRoot
      , resolveKanjiVgRoot
      , findStrokeSvg
      ) where

    import qualified Data.Text as Text
    import System.Directory (doesDirectoryExist, doesFileExist, getCurrentDirectory)
    import System.Environment (lookupEnv)
    import System.FilePath ((</>))

    import Nihongo.Kanji (Kanji, kanjiCodepointHex)
    import Nihongo.Prelude

    -- | Absolute filesystem path to the KanjiVG checkout. Must contain a
    --   `kanji/` subdirectory of `<5-hex>.svg` files.
    newtype KanjiVgRoot = KanjiVgRoot { rootPath :: FilePath }
      deriving stock (Eq, Show)

    -- | Resolve the KanjiVG root using the priority order:
    --     1. the explicit override (e.g. from --kanjivg-dir)
    --     2. the NIHONGO_KANJIVG_DIR env var
    --     3. <cwd>/data/kanjivg
    --   Returns Nothing if none of those exist on disk.
    resolveKanjiVgRoot :: Maybe FilePath -> IO (Maybe KanjiVgRoot)
    resolveKanjiVgRoot override = do
      mEnv <- lookupEnv "NIHONGO_KANJIVG_DIR"
      cwd  <- getCurrentDirectory
      let candidates =
            filter (not . null)
              [ maybe "" id override
              , maybe "" id mEnv
              , cwd </> "data" </> "kanjivg"
              ]
      pickFirstExisting candidates
      where
        pickFirstExisting []     = pure Nothing
        pickFirstExisting (p:ps) = do
          ok <- doesDirectoryExist (p </> "kanji")
          if ok then pure (Just (KanjiVgRoot p)) else pickFirstExisting ps

    -- | Convenience: resolve the root with no override. Errors loudly if no
    --   candidate exists, since most callers cannot meaningfully proceed without
    --   the corpus.
    defaultKanjiVgRoot :: IO KanjiVgRoot
    defaultKanjiVgRoot = do
      mr <- resolveKanjiVgRoot Nothing
      case mr of
        Just r  -> pure r
        Nothing -> ioError (userError msg)
      where
        msg = unlines
          [ "Could not find the KanjiVG corpus."
          , "Tried, in order:"
          , "  1. NIHONGO_KANJIVG_DIR env var"
          , "  2. ./data/kanjivg (relative to current working directory)"
          , "Run `git submodule update --init data/kanjivg` from the project root,"
          , "or set NIHONGO_KANJIVG_DIR to point at a KanjiVG checkout."
          ]

    -- | Look up the SVG path for a `Kanji`. Returns `Nothing` if the file is
    --   absent (KanjiVG does not cover every Unicode CJK codepoint).
    findStrokeSvg :: KanjiVgRoot -> Kanji -> IO (Maybe FilePath)
    findStrokeSvg (KanjiVgRoot root) k = do
      let hex  = Text.unpack (kanjiCodepointHex k)
          path = root </> "kanji" </> (hex <> ".svg")
      ok <- doesFileExist path
      pure (if ok then Just path else Nothing)

Add `Nihongo.Kanji.KanjiVg` to `nihongo-core/nihongo-core.cabal`'s library
`exposed-modules`.

Acceptance: `cabal build all` succeeds. In `cabal repl nihongo-core`:

    >>> import Nihongo.Kanji
    >>> import Nihongo.Kanji.KanjiVg
    >>> root <- defaultKanjiVgRoot
    >>> let Right k = mkKanji '漢'
    >>> findStrokeSvg root k
    Just "/.../data/kanjivg/kanji/06f22.svg"


### Milestone D — Temporary debug subcommand

After this milestone the user can call `nihongo kanji-debug-path <CHAR>` and see the
resolved SVG path (or an error). The subcommand is hidden from the top-level `--help`
output (use `internal` on the `command`) and is removed by EP-5 once `kanji show`
exists.

Create `nihongo-cli/src/Nihongo/Cli/Commands/KanjiDebug.hs`:

    module Nihongo.Cli.Commands.KanjiDebug
      ( KanjiDebugCommand (..)
      , kanjiDebugParser
      , runKanjiDebug
      ) where

    import qualified Data.Text as Text
    import qualified Data.Text.IO as TIO
    import Options.Applicative
        ( Parser
        , argument
        , help
        , long
        , metavar
        , optional
        , str
        , strOption
        )
    import qualified System.IO as IO
    import System.Exit (exitFailure)

    import Nihongo.Kanji (KanjiError (..), mkKanji)
    import Nihongo.Kanji.KanjiVg (findStrokeSvg, resolveKanjiVgRoot)
    import Nihongo.Prelude

    data KanjiDebugCommand = KanjiDebugCommand
      { kdcInput        :: Text
      , kdcRootOverride :: Maybe FilePath
      }
      deriving stock (Show, Eq)

    kanjiDebugParser :: Parser KanjiDebugCommand
    kanjiDebugParser =
      KanjiDebugCommand
        <$> argument str (metavar "CHAR" <> help "Single Japanese character")
        <*> optional (strOption (long "kanjivg-dir"
                              <> metavar "PATH"
                              <> help "Override the KanjiVG root directory"))

    runKanjiDebug :: KanjiDebugCommand -> IO ()
    runKanjiDebug (KanjiDebugCommand input override) =
      case Text.uncons input of
        Nothing                    -> die "expected a single character"
        Just (c, rest)
          | not (Text.null rest)   -> die "expected a single character (got more)"
          | otherwise              ->
              case mkKanji c of
                Left (KanjiOutOfRange ch) ->
                  die ("not a Japanese character: " <> Text.singleton ch)
                Right k -> do
                  mroot <- resolveKanjiVgRoot override
                  case mroot of
                    Nothing -> die "KanjiVG root not found; see --help"
                    Just r  -> do
                      mp <- findStrokeSvg r k
                      case mp of
                        Just p  -> TIO.putStrLn (Text.pack p)
                        Nothing -> die "kanji has no entry in this KanjiVG checkout"
      where
        die msg = TIO.hPutStrLn IO.stderr msg >> exitFailure

Wire it into `Nihongo.Cli.commandParser` by adding a new `command` block:

    <> command "kanji-debug-path"
        (info (CmdKanjiDebug <$> KanjiDebug.kanjiDebugParser)
          (progDesc "(internal) Resolve the KanjiVG SVG path for a character"
        <> internal))

Add the `CmdKanjiDebug KanjiDebug.KanjiDebugCommand` constructor to the `Command` ADT
and a matching arm in `runCommand` that calls `KanjiDebug.runKanjiDebug`. Add the
import `import qualified Nihongo.Cli.Commands.KanjiDebug as KanjiDebug`. Add
`Nihongo.Cli.Commands.KanjiDebug` to `nihongo-cli/nihongo-cli.cabal`'s library
`exposed-modules`.

Note for EP-5: when `kanji show` lands, remove the `kanji-debug-path` command and its
module — the `show` subcommand subsumes it. Record that removal in EP-5's Decision Log.

Acceptance: see Validation and Acceptance.


## Concrete Steps

Run from repo root.

Milestone A:

    git submodule add https://github.com/KanjiVG/kanjivg.git data/kanjivg
    (cd data/kanjivg && git fetch --tags && git checkout r20250816)
    git submodule status
    ls data/kanjivg/kanji/06f22.svg
    # Edit README.md per Plan of Work.

Expected: `git submodule status` shows `<commit-hash> data/kanjivg (r20250816)`. The
`ls` succeeds.

Milestone B:

    # Create nihongo-core/src/Nihongo/Kanji.hs.
    # Add it to nihongo-core.cabal's exposed-modules.
    cabal build all

Milestone C:

    # Create nihongo-core/src/Nihongo/Kanji/KanjiVg.hs.
    # Add it to exposed-modules. Add directory + filepath deps.
    cabal build all
    cabal repl nihongo-core
    # then in the repl: see acceptance above.

Milestone D:

    # Create nihongo-cli/src/Nihongo/Cli/Commands/KanjiDebug.hs.
    # Wire into Nihongo.Cli.
    cabal build all
    cabal run nihongo -- kanji-debug-path 漢
    cabal run nihongo -- kanji-debug-path あ
    cabal run nihongo -- kanji-debug-path A
    cabal run nihongo -- kanji-debug-path 漢字   # too many chars

Expected outputs:

    /Users/shinzui/Keikaku/bokuno/nihongo/data/kanjivg/kanji/06f22.svg
    /Users/shinzui/Keikaku/bokuno/nihongo/data/kanjivg/kanji/03042.svg
    not a Japanese character: A
    expected a single character (got more)

(The exact prefix in the absolute path will vary by working directory; the suffix
`/data/kanjivg/kanji/<hex>.svg` is the part that matters.)


## Validation and Acceptance

The submodule is materialised: `git submodule status` returns one line ending in
`(r20250816)`, and `data/kanjivg/kanji/06f22.svg` exists and is non-empty.

The smart constructor accepts kanji and kana, rejects ASCII: in `cabal repl
nihongo-core`,

    mkKanji '漢' is Right (Kanji '\x6F22')
    mkKanji 'あ' is Right (Kanji '\x3042')
    mkKanji 'A'  is Left (KanjiOutOfRange 'A')

`kanjiCodepointHex` produces the right padded hex: in repl,

    kanjiCodepointHex <$> mkKanji '漢' is Right "06f22"
    kanjiCodepointHex <$> mkKanji 'あ' is Right "03042"

`findStrokeSvg` returns the right path for known characters and `Nothing` for unknown
ones: in repl,

    >>> root <- defaultKanjiVgRoot
    >>> let Right k = mkKanji '漢' in findStrokeSvg root k
    Just "/.../data/kanjivg/kanji/06f22.svg"

The CLI debug subcommand exits zero with the expected path on `nihongo
kanji-debug-path 漢`, and exits non-zero with the expected error on `nihongo
kanji-debug-path A`. The subcommand is invisible in `nihongo --help` because it is
marked `internal`.

Resolution priority test: with `NIHONGO_KANJIVG_DIR=/Users/shinzui/Keikaku/hub/kanjivg
cabal run nihongo -- kanji-debug-path 漢`, the printed path begins with
`/Users/shinzui/Keikaku/hub/kanjivg/`, demonstrating the env-var override works.


## Idempotence and Recovery

`git submodule add` is not idempotent — running it twice errors with "already exists".
If you need to re-run Milestone A, first deinit the submodule:

    git submodule deinit -f data/kanjivg
    git rm -f data/kanjivg
    rm -rf .git/modules/data/kanjivg

then re-add. Better: check `git submodule status` first; if `data/kanjivg` is listed
and at the right commit, skip the milestone entirely.

`cabal build` is idempotent. The Haskell modules can be created and re-edited freely.
If `findStrokeSvg` returns `Nothing` unexpectedly, log the path it constructed
(`putStrLn path`) and run `ls <path>` from the shell — the most common cause is a
missing or stale submodule, fixed with `git submodule update --init data/kanjivg`.


## Interfaces and Dependencies

Cabal dependencies added:

- `nihongo-core/nihongo-core.cabal` library: `directory ^>= 1.3`, `filepath ^>= 1.4`.
  Existing deps (`base`, `text`, `lens`, `generic-lens`, `aeson`, `aeson-casing`,
  `time`) are unchanged.

- `nihongo-cli/nihongo-cli.cabal` library: no new deps; the new module
  `Nihongo.Cli.Commands.KanjiDebug` reuses `optparse-applicative`, `text`, and
  `nihongo-core`.

Exposed modules added:

- `nihongo-core`: `Nihongo.Kanji`, `Nihongo.Kanji.KanjiVg`.
- `nihongo-cli`: `Nihongo.Cli.Commands.KanjiDebug` (temporary; removed by EP-5).

Public APIs subsequent ExecPlans rely on:

- `Nihongo.Kanji.Kanji` (newtype) — used by EP-3 (parser) and EP-5 (command).
- `Nihongo.Kanji.unKanji :: Kanji -> Char` — accessor for the underlying char.
- `Nihongo.Kanji.mkKanji :: Char -> Either KanjiError Kanji` — smart constructor;
  EP-5 calls it after stripping piped input.
- `Nihongo.Kanji.kanjiCodepointHex :: Kanji -> Text` — exposed for completeness;
  EP-3 may use it to label outputs.
- `Nihongo.Kanji.KanjiVg.KanjiVgRoot` — opaque newtype around `FilePath`.
- `Nihongo.Kanji.KanjiVg.resolveKanjiVgRoot :: Maybe FilePath -> IO (Maybe KanjiVgRoot)`
  — EP-5 calls this with the user-supplied `--kanjivg-dir` flag.
- `Nihongo.Kanji.KanjiVg.findStrokeSvg :: KanjiVgRoot -> Kanji -> IO (Maybe FilePath)`
  — EP-3's `parseStrokeOrderFile` (introduced in EP-3) consumes the `FilePath` it returns.

System tools required (provided by `flake.nix` after EP-1):

- `git` ≥ 2.30 — used to add and update the submodule.

Files whose ownership transfers to a later plan:

- `nihongo-cli/src/Nihongo/Cli/Commands/KanjiDebug.hs` — EP-5 deletes this and its
  registration in `Nihongo.Cli.commandParser` once `kanji show` lands. Record the
  deletion in EP-5's Decision Log.
