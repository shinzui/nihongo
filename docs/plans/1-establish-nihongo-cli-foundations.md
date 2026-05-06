---
id: 1
slug: establish-nihongo-cli-foundations
title: "Establish nihongo CLI foundations"
kind: exec-plan
created_at: 2026-05-06T02:27:16Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
master_plan: "docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md"
---

# Establish nihongo CLI foundations

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan a developer who clones the `nihongo` repo and runs `nix develop && cabal
build all` gets a working CLI binary called `nihongo` that already knows how to do four
things even though no real feature has been added yet:

1. Print its version with the embedded git SHA via `nihongo --version` (output looks like
   `nihongo 0.1.0.0 (git: a1b2c3d)`).
2. Show grouped, terminal-width-aware help via `nihongo help` (a list of topics) and
   `nihongo help <topic>` (the topic's contents). The width adapts to the terminal but
   never goes wider than 140 columns; piping the output preserves it byte-for-byte.
3. Emit shell-completion scripts via `nihongo completions bash`, `nihongo completions
   zsh`, and `nihongo completions fish`.
4. Read its main input from stdin when piped: `echo hello | nihongo hello` produces
   `Hello, hello!`. (The `hello` subcommand stays as a placeholder demonstrating the
   pattern; it is replaced by the `kanji` subcommand in the EP-5 plan at
   `docs/plans/5-implement-kanji-show-command.md`.)

The point of this plan is not the four behaviors above per se. The point is that every
later plan in the master plan
`docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md` (EP-2 through
EP-5) starts from a project where the prelude is already meaningful, the cabal `common
common-options` stanza is final, the `flake.nix` provides `rsvg-convert` and a recent
`git`, and the optparse-applicative parser is shaped in a way that does not collapse the
moment a `--width` flag is added (a documented trap; see the Plan of Work). Without
this plan the later plans would each pay a tax to set those things up and the project
would drift from the conventions the rest of the codebase follows.

You will know it works when:

    cabal run nihongo -- --version
    cabal run nihongo -- help
    cabal run nihongo -- help width-demo --width 60
    echo hello | cabal run nihongo -- hello

each succeed and produce the outputs described in the Validation and Acceptance section.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone A: Update `flake.nix` and shared cabal `common-options`. (2026-05-05)
- [x] Milestone A: Verify `nix develop` provides `rsvg-convert` and `git` >= 2.30. (2026-05-05; rsvg-convert from librsvg-2.61.4, git 2.53.0)
- [x] Milestone B: Expand `Nihongo.Prelude` per haskell-jitsurei custom-prelude pattern. (2026-05-05)
- [x] Milestone B: Add `Nihongo.Pretty` ANSI helpers in `nihongo-cli`. (2026-05-05)
- [x] Milestone C: Implement `Nihongo.Cli.Version` with githash + CPP fallback. (2026-05-05)
- [x] Milestone C: Implement `Nihongo.Cli.Stdin` (auto-detect piped input). (2026-05-05)
- [x] Milestone C: Implement `Nihongo.Cli.Width` (terminal-size + paragraph wrap). (2026-05-05)
- [x] Milestone D: Implement `Nihongo.Cli.Help` with embedded markdown topics. (2026-05-05)
- [x] Milestone D: Implement `Nihongo.Cli.Completions` with built-in optparse protocol. (2026-05-05)
- [ ] Milestone E: Restructure `Nihongo.Cli` to use the parser-shape-safe pattern with `version`, `help`, `completions`, and a placeholder `hello` subcommand wired through stdin auto-detection.
- [ ] Milestone E: All commands listed in Validation and Acceptance produce the expected output.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- The existing scaffold's `nihongo-cli/src/Nihongo/Cli.hs` does NOT compile as
  shipped: the `command` field on `Options` and the `command` builder from
  `Options.Applicative` are ambiguously in scope, producing GHC-87543 "Ambiguous
  occurrence 'command'" at both the field-dot use site and the `hsubparser`
  builder. Evidence: `cabal build all` before any edits fails with two GHC-87543
  errors. Fix folded into Milestone E by `import Options.Applicative hiding
  (command)` plus `import qualified Options.Applicative as OA` and using
  `OA.command "hello"`. The `Nihongo.Cli.Help` module already follows this
  qualification pattern.

- `Nihongo.Cli.Version` triggers `-Woverlapping-patterns` because GHC sees the
  `tGitInfoCwdTry` typed-TH splice as a statically known `Right` when `.git`
  is present at compile time, and reports the `Left _` branch as redundant.
  The dual branch is required for portability across `cabal build` (with `.git`)
  and `nix build` (which strips `.git`); we silence the warning per-file with
  `{-# OPTIONS_GHC -Wno-overlapping-patterns #-}` and document the reason in
  the file header.


## Decision Log

Record every decision made while working on the plan.

- Decision: Place CLI infra modules under `nihongo-cli/src/Nihongo/Cli/*` rather than
  `nihongo-core`.
  Rationale: All four modules (Version, Stdin, Width, Help, Completions, Pretty) speak
  to terminal IO, optparse-applicative, or git embedding — none belong in a pure
  library. Keeping them in `nihongo-cli` keeps `nihongo-core` free of `process`,
  `terminal-size`, `githash`, and `file-embed` dependencies.
  Date: 2026-05-05.

- Decision: Drop `module Data.Generics.Labels` and explicit `liftIO` from the
  `Nihongo.Prelude` export list relative to the plan as authored.
  Rationale: `Data.Generics.Labels` is imported with `()` solely for its
  `IsLabel` instance so `OverloadedLabels` resolves `#field` via generic-lens;
  it has no exported names, and re-exporting it triggers
  `-Wdodgy-exports` ("module exports nothing"). `liftIO` is already exported
  by `MonadIO(..)`, and listing it explicitly triggers `-Wduplicate-exports`.
  Both warnings are emitted by `-Wall` (which is in the shared common-options
  stanza). The note in the module header explains why the import remains.
  Date: 2026-05-05.

- Decision: Use `terminal-size` for width detection, never `ansi-terminal`'s
  `getTerminalSize`.
  Rationale: `ansi-terminal`'s implementation writes a cursor-position escape sequence
  to stdout and reads stdin for the response. When stdout is piped this leaks visible
  garbage into the pipe; under non-TTY harnesses (CI, captured tests) it can hang.
  `terminal-size` uses `ioctl(TIOCGWINSZ)` and is silent. The haskell-jitsurei `cli/help-width.md`
  document explicitly warns against the `ansi-terminal` path.
  Date: 2026-05-05.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This is a fresh Haskell project at `/Users/shinzui/Keikaku/bokuno/nihongo` with two cabal
packages already scaffolded. The reader should picture the following layout (paths are
repository-relative):

    nihongo-core/
      nihongo-core.cabal
      src/Nihongo/Prelude.hs        — currently re-exports lens + generic-lens labels only
    nihongo-cli/
      nihongo-cli.cabal
      app/Main.hs                   — calls Nihongo.Cli.runCli
      src/Nihongo/Cli.hs            — has a single `hello` subcommand
    cabal.project                   — lists the two packages
    flake.nix                       — Nix devshell with GHC 9.12 + cabal-install
    fourmolu.yaml, treefmt.nix      — formatting config (do not change)
    LICENSE, README.md, CHANGELOG.md
    .envrc, .gitignore

Both cabal files already share a `common common-options` stanza with `default-language:
GHC2024` and `default-extensions: DeriveAnyClass, DuplicateRecordFields,
OverloadedLabels, OverloadedStrings`. The warning set is `-Wall -Wcompat -Widentities
-Wincomplete-uni-patterns -Wincomplete-record-updates -Wredundant-constraints
-fhide-source-paths -Wmissing-export-lists -Wpartial-fields
-Wmissing-deriving-strategies`.

The current `nihongo-core/src/Nihongo/Prelude.hs` is six lines plus comments; it
re-exports `Control.Lens`, `Data.Generics.Labels` (orphan import), `Data.Generics.Product`,
and `Data.Generics.Sum`. The current `nihongo-cli/src/Nihongo/Cli.hs` defines a `Command
= Hello (Maybe Text)` ADT and a single `hsubparser` with a `hello` subcommand.

The conventions you will follow come from a sibling documentation repository at
`/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/`. You do not need to re-read it; the
patterns are summarized below in their own subsections. When in doubt, the live source
of truth is that repo.

Definitions of terms used below:

- *git submodule*: a pointer in this repository to a specific commit of another git
  repository, stored in `.gitmodules` and as a special tree entry. EP-2 introduces one
  for KanjiVG; this plan only ensures `flake.nix` provides a recent enough `git` to
  consume it.
- *Kitty graphics protocol*: a way for a terminal emulator (Kitty, WezTerm, Ghostty)
  to render pixel images inline with text by reading bytes from a wrapped escape
  sequence. EP-4 implements it; this plan does not.
- *parser-shape trap* (or "help-width parser-shape trap"): a known way to break an
  optparse-applicative help command by writing it as `listFlag <|> showTopicParser <|>
  pure SelectTopics` with `--width` declared only on the `showTopicParser` branch.
  optparse-applicative commits to whichever branch consumes a flag first, so `myapp
  help --width 60` chooses `showTopicParser`, then errors with "Missing TOPIC" because
  no topic argument was given. The fix is one shared `widthOption` declared at the
  same level as the topic argument, with a single combinator that branches on whether
  the topic was supplied. The Plan of Work shows the exact shape.
- *file-embed*: Haskell library that exposes a TemplateHaskell splice
  `embedStringFile :: FilePath -> Q Exp` which compiles a file's bytes into a string
  literal at build time. Useful for shipping help topic markdown alongside the binary.
- *githash*: Haskell library that exposes a TemplateHaskell splice
  `$$tGitInfoCwdTry :: Q (TExp (Either String GitInfo))` returning git metadata
  (commit hash, dirty flag) for the working tree at build time. Returns `Left` when
  there is no `.git` directory (the case under `nix build` since Nix strips it).


### haskell-jitsurei custom-prelude pattern (summary)

A project-wide custom prelude lives in the core library and re-exports a curated
toolkit so application modules import it once and stop fighting per-module imports.
For nihongo, expand `Nihongo.Prelude` to re-export:

- The lens vocabulary it already has: `Control.Lens`, `Data.Generics.Labels` (orphan
  instance, imported with `()`), `Data.Generics.Product`, `Data.Generics.Sum`.
- `Data.Text` as `Text` (just the type plus `Text` itself) and helpers
  `Text.pack`/`Text.unpack` from `Data.Text`. Do NOT re-export `Data.Text` qualified
  contents in unqualified form; consumers should still write `T.foo` for transformations.
  We re-export only `Text` itself unqualified.
- `GHC.Generics (Generic)` and `Data.List.NonEmpty (NonEmpty(..))`.
- `Data.Time (UTCTime, getCurrentTime)`.
- `Control.Monad.IO.Class (MonadIO(..), liftIO)`.
- `Data.Aeson (FromJSON, ToJSON)` and `Data.Aeson.Casing (aesonPrefix, snakeCase)`.

The pattern uses `module X` re-export blocks. Consumers write `import Nihongo.Prelude`
and get all of the above without per-module imports.

Cabal additions to `nihongo-core`: `aeson`, `aeson-casing`, `time`. (The `text`,
`generic-lens`, and `lens` are already there.)


### haskell-jitsurei multiline-strings pattern (summary)

GHC 9.12 introduces the `MultilineStrings` extension. Triple-quoted string literals
strip common leading indentation and one leading and one trailing newline; whitespace-only
lines stay empty. With `OverloadedStrings`, the literal types as `Text` directly. Use
this for help topic stubs and any embedded ASCII art. Add `MultilineStrings` to the
shared cabal `common-options` stanza so every module can use it.

Caveat: multiline strings do not interpolate; for substitution use `Text.replace`.


### haskell-jitsurei version-with-git-sha pattern (summary)

A `Nihongo.Cli.Version` module provides `appVersion :: Text` (cabal version, from the
auto-generated `Paths_nihongo_cli`) and `appVersionWithGit :: Text` (cabal version plus
short SHA in parentheses). The git SHA is acquired via two paths:

- *Cabal build path.* The `githash` library exposes `$$tGitInfoCwdTry`, which is a typed
  TH splice that runs at compile time and returns `Either String GitInfo`. When `.git`
  exists the splice succeeds with the commit hash; when it does not (e.g., under `nix
  build`, which strips `.git` from the source), the splice returns `Left` and a CPP
  fallback path applies.
- *Nix build path.* The flake passes a `-DGIT_HASH="abc1234"` GHC option so a CPP
  `#ifdef GIT_HASH` block compiles the SHA in as a literal. Until we publish a Nix
  package, the CPP path is an unused fallback; record this in the Decision Log.

A `versionInfoOption :: Parser (a -> a)` wraps `Options.Applicative.infoOption` to
register `--version` on the top-level parser.


### haskell-jitsurei stdin-integration pattern (summary)

A `Nihongo.Cli.Stdin` module exposes:

    isStdinPiped :: IO Bool
    getTextInput :: Maybe Text -> IO (Maybe Text)

`isStdinPiped` returns `not <$> hIsTerminalDevice stdin`. `getTextInput` accepts the
positional argument (if any) and returns:

- `Just arg` if the user passed an argument.
- The trimmed contents of stdin if stdin is piped (call `Data.Text.IO.getContents` and
  apply `Data.Text.strip`; an empty result becomes `Nothing`).
- `Nothing` otherwise.

Use `TIO.getContents`, never `pack <$> hGetContents stdin` — the latter does locale
decoding that can mangle UTF-8 input. EP-5 will use this exact module to accept a
piped kanji.


### haskell-jitsurei help-width pattern (summary, with the trap)

A `Nihongo.Cli.Width` module exposes:

    resolveWidth :: Maybe Int -> IO (Maybe Int)
    wrapText     :: Int -> Text -> Text

`resolveWidth Nothing` calls `System.Console.Terminal.Size.size` (returns `Maybe Window`
where `Window` has `width :: Int` and `height :: Int`). If stdout is a TTY and `size`
returns `Just w`, return `Just (min (width w) 140)` (the 140 cap keeps long lines
readable). If stdout is *not* a TTY (`hIsTerminalDevice stdout` returns `False`),
return `Nothing` — meaning "do not wrap; preserve byte-for-byte output for pipes."
`resolveWidth (Just n)` returns `Just n` directly (explicit user input bypasses the
cap).

`wrapText w` splits the input on blank lines into paragraphs. A paragraph whose every
non-empty line begins with two spaces is treated as verbatim (code/transcript) and
emitted unchanged. Other paragraphs are greedy-packed: words are appended to the
current line until the next word would exceed `w`, at which point a newline is
emitted. Words longer than `w` are placed on their own line. Paragraphs are separated
by a single blank line.

THE PARSER-SHAPE TRAP. Suppose a `help` subcommand parser is shaped like this:

    helpCommandParser =
      listFlag <|> (ShowTopic <$> topicArg <*> widthOption)
                <|> pure SelectTopics

`myapp help --width 60` then fails with "Missing TOPIC" because optparse-applicative
greedily commits to `ShowTopic` once it sees `--width`. The fix is one shared
`widthOption` and a single combinator that branches on `Maybe Text`:

    helpCommandParser :: Parser HelpCommand
    helpCommandParser =
      asum
        [ listFlag
        , buildHelp <$> optional topicArg <*> widthOption
        ]
      where
        buildHelp Nothing  w = SelectTopics w
        buildHelp (Just t) w = ShowTopic t w

That single shape carries through both `nihongo help --width 60` (no topic) and
`nihongo help width-demo --width 60` (topic given) without choking.


### haskell-jitsurei help-topics pattern (summary)

A `Nihongo.Cli.Help` module owns:

    data HelpTopic = HelpTopic
      { topicName        :: Text
      , topicDescription :: Text
      , topicContent     :: Text
      }

    helpTopics :: [HelpTopic]

`topicContent` is loaded with `Data.FileEmbed.embedStringFile` at compile time. Topics
live as markdown files under `nihongo-cli/help/<name>.md`. For this plan we embed two
topics:

- `help/about.md` — a one-paragraph project description.
- `help/width-demo.md` — a verbose multi-paragraph fixture used to exercise wrapping.

`runHelpCommand` looks up topics case-insensitively. For `SelectTopics`, it prints a
formatted index. For `ShowTopic name`, it prints that topic's content through `wrapText`.

Cabal: add `file-embed` to `nihongo-cli` deps. Note: file-embed does NOT cause cabal
to re-link when the underlying file changes. Document this caveat in the help module's
top comment so future contributors `touch` the consuming `.hs` file after editing a
markdown topic.


### haskell-jitsurei completions pattern (summary)

A `Nihongo.Cli.Completions` module owns:

    data CompletionsShell = Bash | Zsh | Fish

    runCompletionsCommand :: CompletionsShell -> IO ()

For `Bash`, run the binary's own `--bash-completion-index` protocol via the
`Options.Applicative.bashCompletionScript` helper. For `Zsh`, use
`zshCompletionScript`. For `Fish`, use `fishCompletionScript`. All three are part of
optparse-applicative ≥ 0.18 (already a dependency). The shells learn about
subcommands and flags by introspecting the parser tree, so as long as the parsers have
`progDesc` filled in the completions are useful.


### haskell-jitsurei option-groups pattern (summary)

`optparse-applicative ≥ 0.19` exposes `parserOptionGroup :: String -> Parser a ->
Parser a`. Wrapping an option parser in `parserOptionGroup "Header" parser` causes those
options to render under a labelled section in `--help`. The runtime semantics are
unchanged — pure cosmetic. EP-5 will use this for the `kanji show` subcommand; this
plan introduces no flag groups but bumps `optparse-applicative` to `>= 0.19` so EP-5
can use them.


### kizamu Pretty pattern (summary)

A `Nihongo.Pretty` module re-exports a small set of ANSI styling helpers used by the
same author's `kizamu` project (referenced at
`/Users/shinzui/Keikaku/bokuno/kizamu-project/kizamu/src/Kizamu/Pretty.hs`):

    dim     :: Text -> Text   -- wraps in CSI 2 m / CSI 22 m
    bold    :: Text -> Text   -- wraps in CSI 1 m / CSI 22 m
    colored :: Color -> Text -> Text
    data Color = Red | Green | Yellow | Blue | Magenta | Cyan | White

The implementation is direct concatenation of escape sequences with `Text` (no
external dep needed). EP-4 will use `dim` for the `[Image: 漢]` placeholder; EP-5 will
use `bold` for stroke numbers.


## Plan of Work

The work is in five milestones. Each ends with a runnable check. Do not skip ahead;
each milestone unblocks the next.


### Milestone A — Project plumbing: flake and shared cabal stanza

After this milestone the dev shell provides every system tool the rest of the plans
need, and the shared cabal `common-options` stanza supports `MultilineStrings` and
`PackageImports`.

Edit `flake.nix` so the dev-shell `nativeBuildInputs` list includes `pkgs.librsvg`
(supplies `rsvg-convert`) and `pkgs.gitMinimal` (gives a recent `git` for submodule
operations independent of the host system git). Keep the existing `pkgs.zlib`,
`pkgs.just`, `pkgs.cabal-install`, `pkgs.pkg-config`, and `haskellPackages.ghcWithPackages
(ps: [ ps.haskell-language-server ])`.

Edit both `nihongo-core/nihongo-core.cabal` and `nihongo-cli/nihongo-cli.cabal` so the
shared `common common-options` stanza adds `MultilineStrings` to its `default-extensions`
list. Do not change anything else in that block; the rest of the file edits are
additive (new modules and new build-depends).

Acceptance: `nix develop --command which rsvg-convert` prints a `/nix/store/...` path,
`nix develop --command git --version` prints 2.30 or higher, and `nix develop --command
cabal build all` rebuilds successfully.


### Milestone B — Custom prelude and Pretty helpers

After this milestone every module in either package can `import Nihongo.Prelude` and
get the standard toolkit, and `nihongo-cli` has its `Nihongo.Pretty` ANSI helpers
ready.

Replace the body of `nihongo-core/src/Nihongo/Prelude.hs` with the expanded re-export
list described in the haskell-jitsurei custom-prelude summary above. The exact module
shape:

    module Nihongo.Prelude
      ( -- * Lens vocabulary
        module Control.Lens
        -- * Generic-lens vocabulary
      , module Data.Generics.Labels
      , module Data.Generics.Product
      , module Data.Generics.Sum
        -- * Common types
      , Text
      , Generic
      , NonEmpty (..)
      , UTCTime
        -- * IO
      , MonadIO (..)
      , liftIO
      , getCurrentTime
        -- * Aeson basics
      , FromJSON
      , ToJSON
      ) where

    import Control.Lens
    import Control.Monad.IO.Class (MonadIO (..), liftIO)
    import Data.Aeson (FromJSON, ToJSON)
    import Data.Generics.Labels ()
    import Data.Generics.Product
    import Data.Generics.Sum
    import Data.List.NonEmpty (NonEmpty (..))
    import Data.Text (Text)
    import Data.Time (UTCTime, getCurrentTime)
    import GHC.Generics (Generic)

Update `nihongo-core/nihongo-core.cabal` to add `aeson ^>= 2.2`, `aeson-casing ^>= 0.2`,
and `time ^>= 1.12` to the library `build-depends`.

Create `nihongo-cli/src/Nihongo/Pretty.hs`:

    module Nihongo.Pretty
      ( Color (..)
      , dim
      , bold
      , colored
      ) where

    import Data.Text (Text)
    import qualified Data.Text as Text

    data Color = Red | Green | Yellow | Blue | Magenta | Cyan | White
      deriving stock (Eq, Show)

    dim :: Text -> Text
    dim t = "\ESC[2m" <> t <> "\ESC[22m"

    bold :: Text -> Text
    bold t = "\ESC[1m" <> t <> "\ESC[22m"

    colored :: Color -> Text -> Text
    colored c t = "\ESC[" <> code c <> "m" <> t <> "\ESC[39m"
      where
        code Red = "31"
        code Green = "32"
        code Yellow = "33"
        code Blue = "34"
        code Magenta = "35"
        code Cyan = "36"
        code White = "37"

Add `Nihongo.Pretty` to `nihongo-cli/nihongo-cli.cabal`'s library `exposed-modules`.

Acceptance: `cabal build all` succeeds. `cabal repl nihongo-core:lib:nihongo-core`
launches and `:m + Nihongo.Prelude` followed by `:t (#field :: Lens' Foo Bar)` does not
complain about missing imports of `Control.Lens` or `Data.Generics.Labels`.


### Milestone C — CLI primitives: Version, Stdin, Width

After this milestone three small modules under `nihongo-cli/src/Nihongo/Cli/` hold the
CLI primitives every command will use. They have no consumers yet; Milestone E wires
them in.

Add `githash ^>= 0.1`, `terminal-size ^>= 0.3`, `bytestring ^>= 0.12` to
`nihongo-cli/nihongo-cli.cabal`'s library `build-depends`.

Create `nihongo-cli/src/Nihongo/Cli/Version.hs`:

    {-# LANGUAGE CPP #-}
    {-# LANGUAGE TemplateHaskell #-}

    module Nihongo.Cli.Version
      ( appVersion
      , appVersionWithGit
      , versionInfoOption
      ) where

    import Data.Text (Text)
    import qualified Data.Text as Text
    import Data.Version (showVersion)
    import GitHash (giHash, tGitInfoCwdTry)
    import Options.Applicative (Parser, infoOption, long, help, hidden)
    import Paths_nihongo_cli (version)

    appVersion :: Text
    appVersion = Text.pack (showVersion version)

    appVersionWithGit :: Text
    appVersionWithGit =
      case gitSha of
        Just sha -> appVersion <> " (git: " <> sha <> ")"
        Nothing  -> appVersion
      where
        gitSha :: Maybe Text
        gitSha =
    #ifdef GIT_HASH
          Just (Text.pack GIT_HASH)
    #else
          case $$tGitInfoCwdTry of
            Right gi -> Just (Text.take 7 (Text.pack (giHash gi)))
            Left _   -> Nothing
    #endif

    versionInfoOption :: Parser (a -> a)
    versionInfoOption =
      infoOption (Text.unpack appVersionWithGit)
        ( long "version"
       <> help "Print the version and exit"
       <> hidden
        )

Note the use of `Paths_nihongo_cli`: cabal autogenerates this module per package; the
import works because `nihongo-cli` is the executable's own package.

Create `nihongo-cli/src/Nihongo/Cli/Stdin.hs`:

    module Nihongo.Cli.Stdin
      ( isStdinPiped
      , getTextInput
      ) where

    import Data.Text (Text)
    import qualified Data.Text as Text
    import qualified Data.Text.IO as TIO
    import System.IO (hIsTerminalDevice, stdin)

    isStdinPiped :: IO Bool
    isStdinPiped = not <$> hIsTerminalDevice stdin

    getTextInput :: Maybe Text -> IO (Maybe Text)
    getTextInput (Just t) = pure (Just t)
    getTextInput Nothing  = do
      piped <- isStdinPiped
      if piped
        then do
          contents <- TIO.getContents
          let trimmed = Text.strip contents
          pure (if Text.null trimmed then Nothing else Just trimmed)
        else pure Nothing

Create `nihongo-cli/src/Nihongo/Cli/Width.hs`:

    module Nihongo.Cli.Width
      ( resolveWidth
      , wrapText
      ) where

    import Data.Text (Text)
    import qualified Data.Text as Text
    import System.Console.Terminal.Size (size, Window (..))
    import System.IO (hIsTerminalDevice, stdout)

    -- | Cap auto-detected width at this many columns for readability.
    maxAutoWidth :: Int
    maxAutoWidth = 140

    resolveWidth :: Maybe Int -> IO (Maybe Int)
    resolveWidth (Just n) = pure (Just n)
    resolveWidth Nothing  = do
      isTty <- hIsTerminalDevice stdout
      if not isTty
        then pure Nothing
        else do
          mw <- size
          pure $ case mw of
            Nothing                     -> Nothing
            Just (Window { width = w }) -> Just (min w maxAutoWidth)

    wrapText :: Int -> Text -> Text
    wrapText w input = Text.intercalate "\n\n" (map wrapPara paragraphs)
      where
        paragraphs = Text.splitOn "\n\n" input
        wrapPara p
          | isVerbatim p = p
          | otherwise    = greedyWrap w (Text.words p)
        isVerbatim p =
          all (\l -> Text.null l || Text.isPrefixOf "  " l)
              (Text.splitOn "\n" p)

    greedyWrap :: Int -> [Text] -> Text
    greedyWrap w = Text.intercalate "\n" . go [] 0
      where
        go acc _ []     = [Text.unwords (reverse acc)]
        go acc col (x:xs)
          | null acc                = go [x] (Text.length x) xs
          | col + 1 + Text.length x <= w =
              go (x:acc) (col + 1 + Text.length x) xs
          | otherwise =
              Text.unwords (reverse acc) : go [x] (Text.length x) xs

Add `Nihongo.Cli.Version`, `Nihongo.Cli.Stdin`, and `Nihongo.Cli.Width` to
`nihongo-cli/nihongo-cli.cabal`'s library `exposed-modules`.

Acceptance: `cabal build all` succeeds.


### Milestone D — CLI primitives: Help and Completions

After this milestone two more modules under `nihongo-cli/src/Nihongo/Cli/` provide
help-topic browsing and shell completion script generation. They are still not wired
into `Nihongo.Cli`; Milestone E does that.

Add `file-embed ^>= 0.0.16` to `nihongo-cli/nihongo-cli.cabal`'s library `build-depends`.

Create `nihongo-cli/help/about.md` (raw markdown, no frontmatter):

    # About nihongo

    nihongo is a terminal-first Japanese learning companion for studying kanji,
    vocabulary, readings, stroke order, and grammar directly from the command line. It
    is designed for fast, keyboard-driven workflows and daily practice.

    Run `nihongo help` to see the available topics, and `nihongo help <topic>` to read
    one. Every command supports `--help` for a short reference.

Create `nihongo-cli/help/width-demo.md` with a long paragraph plus an indented
verbatim block, used to exercise `wrapText` end-to-end:

    # Width demo topic

    This topic exists to demonstrate that long paragraphs are wrapped to the terminal
    width or to an explicit `--width` value. When you pass `nihongo help width-demo
    --width 40` you should see this paragraph reflow to roughly 40 columns. When you
    pipe the output through a non-TTY consumer (for example, `nihongo help width-demo
    | cat`) it should remain unwrapped, because byte-stable output is the right
    behaviour for piped readers.

      this is a verbatim block
      it should not be reflowed
      regardless of width settings

    A second paragraph follows the verbatim block to confirm that wrapping resumes for
    plain prose.

Create `nihongo-cli/src/Nihongo/Cli/Help.hs`:

    {-# LANGUAGE TemplateHaskell #-}

    module Nihongo.Cli.Help
      ( HelpTopic (..)
      , HelpCommand (..)
      , helpTopics
      , helpCommandParser
      , runHelpCommand
      ) where

    import Data.FileEmbed (embedStringFile)
    import Data.Foldable (for_)
    import qualified Data.List as List
    import Data.Text (Text)
    import qualified Data.Text as Text
    import qualified Data.Text.IO as TIO
    import Options.Applicative
        ( Parser
        , argument
        , help
        , long
        , metavar
        , option
        , optional
        , short
        , str
        )
    import qualified Options.Applicative as OA

    import Nihongo.Cli.Width (resolveWidth, wrapText)

    data HelpTopic = HelpTopic
      { topicName        :: Text
      , topicDescription :: Text
      , topicContent     :: Text
      }

    helpTopics :: [HelpTopic]
    helpTopics =
      [ HelpTopic "about"      "Project overview" $(embedStringFile "help/about.md")
      , HelpTopic "width-demo" "Width-handling fixture topic" $(embedStringFile "help/width-demo.md")
      ]

    data HelpCommand
      = ListTopics
      | ShowTopic Text (Maybe Int)
      deriving stock (Show, Eq)

    helpCommandParser :: Parser HelpCommand
    helpCommandParser =
      buildHelp <$> optional topicArg <*> widthOption
      where
        topicArg = argument str (metavar "TOPIC" <> help "Help topic to display")
        widthOption =
          optional $
            option OA.auto
              ( long "width"
             <> metavar "COLUMNS"
             <> help "Wrap output to this many columns"
              )
        buildHelp Nothing  _ = ListTopics
        buildHelp (Just t) w = ShowTopic t w

    runHelpCommand :: HelpCommand -> IO ()
    runHelpCommand ListTopics = do
      TIO.putStrLn "Available help topics:"
      for_ helpTopics $ \HelpTopic{topicName, topicDescription} ->
        TIO.putStrLn ("  " <> topicName <> "  -- " <> topicDescription)
      TIO.putStrLn "\nRun `nihongo help <topic>` to read one."
    runHelpCommand (ShowTopic name maybeW) = do
      let needle = Text.toLower name
      case List.find (\t -> Text.toLower (topicName t) == needle) helpTopics of
        Nothing ->
          TIO.putStrLn ("Unknown help topic: " <> name <> ". Run `nihongo help` for the list.")
        Just topic -> do
          mw <- resolveWidth maybeW
          let body = topicContent topic
          TIO.putStrLn $ case mw of
            Nothing -> body
            Just w  -> wrapText w body

Note the parser shape: `buildHelp <$> optional topicArg <*> widthOption`. Both
`topicArg` and `widthOption` are siblings of the same applicative; there is no
left-biased `<|>` that could prefer one branch over the other. This is the
parser-shape-safe pattern from the haskell-jitsurei `cli/help-width.md` document.

Create `nihongo-cli/src/Nihongo/Cli/Completions.hs`:

    module Nihongo.Cli.Completions
      ( CompletionsShell (..)
      , completionsCommandParser
      , runCompletionsCommand
      ) where

    import Data.Text (Text)
    import qualified Data.Text.IO as TIO
    import Options.Applicative
        ( Parser
        , argument
        , help
        , maybeReader
        , metavar
        )

    data CompletionsShell = Bash | Zsh | Fish
      deriving stock (Show, Eq)

    completionsCommandParser :: Parser CompletionsShell
    completionsCommandParser =
      argument (maybeReader parseShell)
        ( metavar "SHELL" <> help "Target shell: bash | zsh | fish" )
      where
        parseShell "bash" = Just Bash
        parseShell "zsh"  = Just Zsh
        parseShell "fish" = Just Fish
        parseShell _      = Nothing

    -- | Print the completion script for the given shell, by re-invoking the
    --   binary with optparse-applicative's built-in completion-script flag.
    --   We do not call the script generator directly here to avoid taking a
    --   dependency on the precise parser tree at this point in the code; instead
    --   the binary printing the completion is the same binary the user runs, so
    --   the protocol works automatically.
    runCompletionsCommand :: CompletionsShell -> IO ()
    runCompletionsCommand sh = do
      let progName = "nihongo"
      let scriptText = case sh of
            Bash ->
              "_nihongo_completions() {\n"
              <> "  local CMDLINE\n"
              <> "  local IFS=$'\\n'\n"
              <> "  CMDLINE=(--bash-completion-index $COMP_CWORD)\n"
              <> "  for arg in \"${COMP_WORDS[@]}\"; do\n"
              <> "    CMDLINE=(\"${CMDLINE[@]}\" --bash-completion-word \"$arg\")\n"
              <> "  done\n"
              <> "  COMPREPLY=( $(\"" <> progName <> "\" \"${CMDLINE[@]}\") )\n"
              <> "}\n"
              <> "complete -o filenames -F _nihongo_completions " <> progName <> "\n"
            Zsh ->
              "#compdef " <> progName <> "\n"
              <> "_nihongo() {\n"
              <> "  local words completions\n"
              <> "  read -cA words\n"
              <> "  if [[ \"${words[$CURRENT]}\" == --* ]]; then\n"
              <> "    completions=($(\"" <> progName <> "\" --bash-completion-index $CURRENT --bash-completion-word \"${words[@]}\"))\n"
              <> "  else\n"
              <> "    completions=($(\"" <> progName <> "\" --bash-completion-index $CURRENT --bash-completion-word \"${words[@]}\"))\n"
              <> "  fi\n"
              <> "  reply=( \"${(ps:\\n:)completions}\" )\n"
              <> "}\n"
              <> "compctl -K _nihongo " <> progName <> "\n"
            Fish ->
              "function _nihongo_completion\n"
              <> "  set -l cmd (commandline -opc) (commandline -ct)\n"
              <> "  " <> progName <> " --bash-completion-index (count $cmd) --bash-completion-word $cmd\n"
              <> "end\n"
              <> "complete -c " <> progName <> " -f -a '(_nihongo_completion)'\n"
      TIO.putStr scriptText

Add `Nihongo.Cli.Help` and `Nihongo.Cli.Completions` to `nihongo-cli/nihongo-cli.cabal`'s
library `exposed-modules`.

Acceptance: `cabal build all` succeeds. `cabal run nihongo-cli:lib:nihongo-cli`-style
checks aren't applicable since these modules have no entry point yet; Milestone E
wires them in.


### Milestone E — Top-level CLI restructure

After this milestone the `nihongo` executable exposes the four behaviors listed in
Purpose / Big Picture. This is the milestone that ties it all together.

Replace the body of `nihongo-cli/src/Nihongo/Cli.hs` with a top-level parser that
includes `--version` (via `versionInfoOption`) and four subcommand groups: `Lookup`
(currently empty — the `kanji` subcommand will land here in EP-5; the group is wired
in as a forward-compatible placeholder so EP-5 has nothing to add to the top-level
parser besides its own subcommand), `Help` (`help`), `Completions` (`completions`),
and `Examples` (`hello` — kept as a placeholder; EP-5 may remove it or keep it).
Concretely:

    module Nihongo.Cli
      ( runCli
      ) where

    import Data.Foldable (traverse_)
    import Data.Text (Text)
    import qualified Data.Text as Text
    import qualified Data.Text.IO as TIO
    import Options.Applicative

    import qualified Nihongo.Cli.Completions as Completions
    import qualified Nihongo.Cli.Help        as Help
    import qualified Nihongo.Cli.Stdin       as Stdin
    import           Nihongo.Cli.Version     (versionInfoOption)

    data Command
      = CmdHello (Maybe Text)
      | CmdHelp Help.HelpCommand
      | CmdCompletions Completions.CompletionsShell
      deriving stock (Show, Eq)

    newtype Options = Options { command :: Command }
      deriving stock (Show, Eq)

    runCli :: IO ()
    runCli = do
      opts <- execParser parserInfo
      runCommand opts.command

    parserInfo :: ParserInfo Options
    parserInfo =
      info (optionsParser <**> helper <**> versionInfoOption)
        ( fullDesc
       <> progDesc "Terminal-first Japanese learning companion."
       <> header "nihongo - kanji, vocabulary, readings, stroke order, and grammar from the command line."
        )

    optionsParser :: Parser Options
    optionsParser = Options <$> commandParser

    commandParser :: Parser Command
    commandParser =
      hsubparser
        ( command "hello" (info helloParser
            (progDesc "Print a greeting (placeholder example)"))
       <> command "help" (info (CmdHelp <$> Help.helpCommandParser)
            (progDesc "Show help topics. Use `help` for the list, `help <topic>` to read one."))
       <> command "completions" (info (CmdCompletions <$> Completions.completionsCommandParser)
            (progDesc "Print a shell completion script (bash | zsh | fish)"))
        )

    helloParser :: Parser Command
    helloParser =
      CmdHello <$> optional (strOption (long "name" <> metavar "NAME" <> help "Whom to greet"))

    runCommand :: Command -> IO ()
    runCommand (CmdHello mName) = do
      resolved <- Stdin.getTextInput mName
      let target = case resolved of
            Just t  -> t
            Nothing -> Text.pack "nihongo"
      traverse_ TIO.putStrLn [Text.pack "Hello, " <> target <> Text.pack "!"]
    runCommand (CmdHelp hc)         = Help.runHelpCommand hc
    runCommand (CmdCompletions sh)  = Completions.runCompletionsCommand sh

Two notes on the structure:

The `--version` flag is attached to the top-level parser, not as a subcommand. This is
the conventional optparse-applicative pattern: `infoOption` short-circuits parsing so
`--version` works regardless of which subcommand follows.

The `hello` subcommand now consults `Stdin.getTextInput`. If the user passes `--name
NAME`, that wins; if stdin is piped, the piped text wins; otherwise it greets
"nihongo". This demonstrates the stdin pattern that EP-5 will reuse for `kanji show`.

Acceptance: see Validation and Acceptance.


## Concrete Steps

Run from repository root `/Users/shinzui/Keikaku/bokuno/nihongo` unless stated otherwise.

Initial sanity check (before any edits):

    nix develop --command cabal build all
    cabal run nihongo -- hello --name world

Expected: build succeeds; output is `Hello, world!`.

Milestone A:

    # Edit flake.nix and both .cabal files per Plan of Work.
    nix develop --command which rsvg-convert
    nix develop --command git --version
    nix develop --command cabal build all

Expected: `which rsvg-convert` prints a path; `git --version` ≥ 2.30; build succeeds.

Milestone B:

    # Edit nihongo-core/src/Nihongo/Prelude.hs and nihongo-core/nihongo-core.cabal.
    # Create nihongo-cli/src/Nihongo/Pretty.hs and add to nihongo-cli.cabal.
    cabal build all

Expected: build succeeds. `cabal repl nihongo-core` followed by
`import Nihongo.Prelude` then `:t getCurrentTime` prints `getCurrentTime :: IO UTCTime`.

Milestone C:

    # Edit nihongo-cli/nihongo-cli.cabal to add deps and modules.
    # Create the three modules under nihongo-cli/src/Nihongo/Cli/.
    cabal build all

Expected: build succeeds.

Milestone D:

    # Create the help/ directory and two markdown files at nihongo-cli/help/.
    # Create the two modules.
    cabal build all

Expected: build succeeds.

Milestone E:

    # Replace nihongo-cli/src/Nihongo/Cli.hs.
    cabal build all
    cabal run nihongo -- --version
    cabal run nihongo -- help
    cabal run nihongo -- help about
    cabal run nihongo -- help width-demo --width 40
    cabal run nihongo -- help width-demo --width 200
    echo hello | cabal run nihongo -- hello
    cabal run nihongo -- completions bash | head -5

See Validation and Acceptance for expected outputs.


## Validation and Acceptance

`cabal run nihongo -- --version` prints a single line whose form is `nihongo 0.1.0.0
(git: <7-hex-chars>)` when the working tree is a git checkout, or `nihongo 0.1.0.0`
when no `.git` is present.

`cabal run nihongo -- help` prints (output may differ in spacing):

    Available help topics:
      about       -- Project overview
      width-demo  -- Width-handling fixture topic

    Run `nihongo help <topic>` to read one.

`cabal run nihongo -- help about` prints the contents of
`nihongo-cli/help/about.md`, wrapped to the terminal width. If the output is captured
into a non-TTY (`cabal run nihongo -- help about | cat`), the body must be byte-stable
with the source file (no wrapping applied).

`cabal run nihongo -- help width-demo --width 40` produces output where the prose
paragraphs are wrapped to roughly 40 columns and the indented verbatim block is
preserved unchanged.

`cabal run nihongo -- help width-demo --width 200` produces unwrapped prose (since 200
is wider than the source).

`echo hello | cabal run nihongo -- hello` prints `Hello, hello!`. With the same
invocation but stdin closed (`cabal run nihongo -- hello < /dev/null`) the output is
`Hello, nihongo!` because no positional flag was given.

`cabal run nihongo -- completions bash | head -5` prints the first five lines of a
bash completion script that begins with `_nihongo_completions() {`. Equivalent for
`zsh` (begins with `#compdef nihongo`) and `fish` (begins with `function
_nihongo_completion`).

Negative tests: `cabal run nihongo -- help nonexistent` prints `Unknown help topic:
nonexistent. Run \`nihongo help\` for the list.` and exits zero.


## Idempotence and Recovery

All edits in this plan are idempotent: re-running `cabal build all` is safe; re-editing
`flake.nix` and re-entering the shell is safe; the same markdown files can be
re-embedded with no effect. If `cabal` cannot resolve `optparse-applicative >= 0.18` or
`githash`, run `nix develop --command cabal update` first — the dev shell ships
`cabal-install` and the Hackage index needs to be primed once per fresh checkout.

Recovery for a half-applied milestone: `git status` shows the new files; `git
restore <path>` reverts an edit; `git clean -nd nihongo-cli/src/Nihongo/Cli/` shows new
files about to be removed (use `-fd` to actually remove them).

Caveat about `file-embed`: editing a `.md` under `nihongo-cli/help/` does not cause
cabal to relink the executable. After such edits, `touch nihongo-cli/src/Nihongo/Cli/Help.hs`
or run `cabal clean && cabal build all` to force a rebuild.


## Interfaces and Dependencies

Cabal dependencies added in this plan (lower bounds chosen to match the haskell-jitsurei
patterns):

`nihongo-core/nihongo-core.cabal` library: `aeson ^>= 2.2`, `aeson-casing ^>= 0.2`,
`time ^>= 1.12`. Existing deps (`base`, `text`, `lens`, `generic-lens`) are unchanged.

`nihongo-cli/nihongo-cli.cabal` library: `bytestring ^>= 0.12`, `file-embed ^>= 0.0.16`,
`githash ^>= 0.1`, `terminal-size ^>= 0.3`. The existing `optparse-applicative >= 0.18`
constraint is bumped to `>= 0.19` so EP-5 may use `parserOptionGroup`. The existing
`nihongo-core` dep is unchanged.

Exposed modules added:

- `nihongo-core`: no new modules; `Nihongo.Prelude` body is rewritten.
- `nihongo-cli`: `Nihongo.Pretty`, `Nihongo.Cli.Version`, `Nihongo.Cli.Stdin`,
  `Nihongo.Cli.Width`, `Nihongo.Cli.Help`, `Nihongo.Cli.Completions`.

Public APIs that subsequent ExecPlans rely on:

- `Nihongo.Prelude` re-exports as listed in Milestone B. Subsequent plans `import
  Nihongo.Prelude` and assume `Text`, `Generic`, `MonadIO`, `liftIO`, `UTCTime`,
  `getCurrentTime`, `FromJSON`, `ToJSON`, `NonEmpty`, plus the lens / generic-lens
  vocabulary.
- `Nihongo.Pretty.dim`, `Nihongo.Pretty.bold`, `Nihongo.Pretty.colored` (with
  `Color`). EP-4 uses `dim` for the `[Image: <kanji>]` fallback; EP-5 uses `bold` for
  stroke numbers.
- `Nihongo.Cli.Stdin.getTextInput :: Maybe Text -> IO (Maybe Text)`. EP-5 uses this to
  accept a piped kanji.
- `Nihongo.Cli.Width.resolveWidth :: Maybe Int -> IO (Maybe Int)` and
  `Nihongo.Cli.Width.wrapText :: Int -> Text -> Text`. EP-5 uses these to wrap stroke-order
  prose output.
- `Nihongo.Cli.Help.HelpTopic` and `helpTopics`. EP-5 extends `helpTopics` by adding
  the `kanji-show` topic.

System tools that must be on `PATH` after `nix develop`:

- `rsvg-convert` (from `librsvg`). EP-4 calls it.
- `git` ≥ 2.30. EP-2 uses it for the submodule.

Files whose ownership transfers to a later plan:

- `nihongo-cli/src/Nihongo/Cli.hs` — EP-5 will add a `kanji` subcommand. Follow the
  pattern: a sibling module `Nihongo.Cli.Commands.Kanji` exporting a `parser :: Parser
  KanjiCommand` and `runCommand :: KanjiCommand -> IO ()`, wired into the
  `commandParser` block in `Nihongo.Cli`.
