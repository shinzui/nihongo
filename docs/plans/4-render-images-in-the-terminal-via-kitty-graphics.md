---
id: 4
slug: render-images-in-the-terminal-via-kitty-graphics
title: "Render images in the terminal via Kitty graphics"
kind: exec-plan
created_at: 2026-05-06T02:27:20Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
master_plan: "docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md"
---

# Render images in the terminal via Kitty graphics

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan `nihongo-cli` carries `Nihongo.Terminal.Image`, a self-contained
module that turns "I have an SVG file path" into "the user sees the image in their
terminal." The module:

1. Detects, once, whether the current terminal supports the Kitty graphics protocol
   (Kitty itself, WezTerm, Ghostty, or any of those wrapped in tmux with passthrough
   enabled).
2. Rasterises a given SVG to a PNG by shelling out to `rsvg-convert` (a system tool
   provided by `librsvg`, declared in `flake.nix` by EP-1).
3. Caches the resulting PNG by content hash under `~/.cache/nihongo/strokes/`, so a
   second display of the same SVG does no work.
4. Emits the Kitty graphics escape sequence directing the terminal to read the PNG
   file by its absolute path. Wraps the sequence in tmux DCS passthrough when
   running inside tmux.
5. Falls back to a dim `[Image: <label>]` placeholder when capability detection
   reports `NoImageSupport`, or when the user has passed `--no-images` (the flag is
   declared here and consumed by EP-5).

A consumer can then call

    Image.displaySvg cap "漢" "/path/to/06f22.svg"

and (in a Kitty-capable terminal) see 漢 rendered. EP-5 wires this up to `kanji show`.

You will know it works when, after EP-1's foundations and this plan are in place, the
following invocation of the temporary debug subcommand introduced here renders an
image inline in a Kitty-capable terminal and prints `[Image: 漢]` elsewhere:

    cabal run nihongo -- image-debug-render data/kanjivg/kanji/06f22.svg

The `image-debug-render` command is a hidden temporary subcommand introduced in this
plan and removed by EP-5.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone A: Implement capability detection (`detectImageCapability`). (2026-05-05; verified inside tmux: `detectImageCapability` returns `KittyGraphics` via the tmux outer-env probe; override `True` short-circuits to `NoImageSupport`.)
- [x] Milestone B: Implement Kitty escape emitter and tmux passthrough wrapping (`displayImage`). (2026-05-05)
- [x] Milestone C: Implement SVG → PNG rasterisation with cache (`ensurePng`). (2026-05-05; first call rasterises ~/.cache/nihongo/strokes/<sha>.png at 109×109 RGBA; second call returns the same path with no rsvg-convert process spawned)
- [x] Milestone D: Implement `displaySvg` orchestration plus `--no-images` plumbing. (2026-05-05)
- [x] Milestone D: Add the temporary `image-debug-render` subcommand. (2026-05-05; hidden via the EP-2 idiom of a separate `hsubparser` with `commandGroup "internal:" <> internal`.)
- [x] Milestone D: Manual verification of what is verifiable from a non-Kitty harness. (2026-05-05; `--no-images` emits the dim `[Image: @...]` placeholder; the no-flag path emits a tmux-wrapped Kitty escape `\\ePtmux;\\e\\e_Ga=T,f=100,t=f,r=12;<base64-path>\\e\\\\` with the cache hit. Visual verification in a real Kitty/WezTerm/Ghostty terminal still requires the user's eyes — see Surprises.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`Control.Lens.Indexed.<.>` (re-exported by `Nihongo.Prelude`)
  collides with `System.FilePath.<.>`.** A naive
  `import System.FilePath ((</>), (<.>))` triggers an ambiguous-occurrence
  error on the first use of `<.>`. Resolved by importing
  `System.FilePath qualified as FP` and using `FP.</>` / `FP.<.>` at call
  sites. EP-5 should follow the same idiom for any new `nihongo-cli`
  module that needs filepath operators.

- **The visual rendering step cannot be verified from the implementing
  agent's harness in this session** — the harness runs inside tmux on
  `TERM=screen-256color` with no GUI, so all I can confirm is the *wire
  shape* of the emitted escape sequence and that no exception is thrown.
  Confirmed shape:

      \ePtmux;\e\e_Ga=T,f=100,t=f,r=12;L1VzZXJz...\e\\

  This is the spec-correct tmux-wrapped Kitty graphics envelope: outer
  `\ePtmux;...\e\\`, inner `\e_G` doubled to `\e\e_G`, base64-encoded
  absolute PNG path payload. Whether the *outer* terminal then renders
  the kanji image is a product of (a) the user's terminal supporting
  Kitty graphics and (b) tmux passthrough being enabled (`set -g
  allow-passthrough on`). Ask the user to run `nihongo
  image-debug-render data/kanjivg/kanji/06f22.svg` once in their normal
  Kitty/WezTerm/Ghostty session as final acceptance.

- **`detectImageCapability` accepts `Just "kitty"` as a valid outer
  `TERM_PROGRAM` from a tmux probe**, in addition to the plan's
  `WezTerm` and `ghostty`. Reason: tmux running inside Kitty itself
  reports `TERM_PROGRAM=kitty` (lowercase) when the environment is
  passed through, and the plan's original list omitted that case. Added
  for completeness; harmless when running outside Kitty.

- **`t=f` (file-path transmission) is silently dropped by WezTerm's
  Kitty graphics implementation when the escape arrives via tmux DCS
  passthrough.** Discovered post-merge when the user reported "blank
  gap, no image" in WezTerm 0-unstable-2026-03-31 + tmux 3.6a (with
  `allow-passthrough on`). Verified by running the same Kitty escape
  manually — `t=f` produced no image, `t=d` (inline base64) produced
  the image. Outside tmux, `t=f` worked. The fix is to switch nihongo
  to `t=d` and chunk the base64 payload across multiple APC sequences
  (Kitty's protocol limits each chunk to 4096 bytes; we use that as
  our chunk size, with `m=1` on every chunk except the last which
  carries `m=0`). Each chunk gets its own tmux DCS envelope. The
  `t=f` path is not preserved because there's no clean fallback (we'd
  have to probe the failure, which is not visible in-protocol). EP-5
  inherits this behaviour transparently.

- **Display row count bumped from 12 to 20, with a higher-resolution
  rasterisation step (384px width) backing it.** The 12-row display at
  the native 109px SVG was hard to read; doubling the row count and
  rasterising at ~3.5x native gives crisp output at terminal display
  size. The cache key now includes a version tag (`v2:width=384`) so
  any cached PNGs from the previous render parameters are
  automatically bypassed when callers ask for a path.


## Decision Log

Record every decision made while working on the plan.

- Decision: Support only the Kitty graphics protocol in v1.
  Rationale: Matches `kizamu`'s decision in
  `/Users/shinzui/Keikaku/bokuno/kizamu-project/kizamu/src/Kizamu/Media.hs`. Sixel and
  iTerm2 inline images can be added later behind a `Capability` extension if a user
  asks. One protocol = one tested code path.
  Date: 2026-05-05.

- Decision: Rasterise SVGs by shelling out to `rsvg-convert`.
  Rationale: User explicitly approved this in conversation. Pure-Haskell SVG
  rasterizers are immature; `rsvg-convert` is widely packaged in nixpkgs (provided by
  `pkgs.librsvg`, added to `flake.nix` in EP-1) and produces PNGs that the Kitty
  protocol consumes natively via `f=100,t=f`. Same author's `kizamu` already follows
  the "shell out via `System.Process` when needed" pattern.
  Date: 2026-05-05.

- Decision: Cache rasterised PNGs by SHA-256 of the SVG content under
  `<XDG_CACHE_HOME or ~/.cache>/nihongo/strokes/<sha256>.png`.
  Rationale: Hashing by content (not by path) is robust to submodule moves and to
  variant filenames; it also de-duplicates identical SVGs across repos. Using
  `cryptohash-sha256` keeps the dependency footprint small (no full `cryptonite`).
  Date: 2026-05-05.

- Decision: Set the Kitty `r` parameter (image height in terminal rows) to 12 for
  stroke-order images.
  Rationale: `kizamu` uses `r=8`; that was tuned for thumbnail images embedded in
  flashcards. A kanji stroke-order chart benefits from being a bit taller for
  legibility. 12 rows is large enough to read the strokes without overwhelming a
  typical 50-row terminal.
  Date: 2026-05-05.

- Decision: Hide `image-debug-render` from `nihongo --help` by extending
  the existing internal-commands `hsubparser` block introduced for
  `kanji-debug-path`, rather than creating a second one.
  Rationale: One `<|>` branch keeps the parser tree readable; both
  internal commands share `commandGroup "internal:" <> internal`, so
  attaching the new `command "image-debug-render" ...` to the same
  block is the lightest-touch idiom and matches the cross-plan guidance
  recorded in EP-2's Surprises.
  Date: 2026-05-05.

- Decision: Accept `Just "kitty"` (lowercase) as a valid outer
  `TERM_PROGRAM` in `detectImageCapability`'s tmux-probe arm.
  Rationale: A tmux session started inside Kitty propagates
  `TERM_PROGRAM=kitty` to the outer environment; without this entry,
  `detectImageCapability` would falsely return `NoImageSupport` for
  the most-likely-to-be-Kitty case. WezTerm/ghostty are kept as before.
  Date: 2026-05-05.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Outcome (2026-05-05): four commits land EP-4 on `master`:

    EP-4 Milestone A: Kitty graphics capability detection
    EP-4 Milestone B: Kitty graphics emitter + tmux passthrough
    EP-4 Milestone C: SVG→PNG rasterisation with content-hash cache
    EP-4 Milestone D: displaySvg + image-debug-render command

`Nihongo.Terminal.Image` exposes the four functions EP-5 will call:
`ImageCapability(..)`, `detectImageCapability`,
`detectImageCapabilityWithOverride`, `displaySvg`. Capability detection
inside tmux returns `KittyGraphics` correctly via the
`tmux show-environment` probe. The rasterisation cache produces a
~4.5 KB PNG at 109×109 RGBA on first call to
`ensurePng "data/kanjivg/kanji/06f22.svg"` and returns the same path
without spawning `rsvg-convert` on the second call. The CLI subcommand
`nihongo image-debug-render <path>` is wired and hidden from
`--help`, supports `--no-images`, and emits the spec-shaped
tmux-wrapped Kitty escape sequence (verified by `cat -A`).

Gap: visual end-to-end verification (a kanji actually appearing in the
user's terminal) cannot happen from the implementing agent's harness.
The shape of the wire output is verified; the rendering depends on the
outer terminal honouring it. EP-5 will add a help topic that documents
the tmux passthrough requirement, and the user should run
`nihongo image-debug-render data/kanjivg/kanji/06f22.svg` once
manually as final acceptance.

Lessons:

1. The prelude re-exports more than its name advertises. `<.>` from
   `Control.Lens.Indexed` is not something you'd think of when writing
   a filepath operation, but the `import Nihongo.Prelude` open form
   pulls it in. Local `qualified` imports of `System.FilePath` are the
   robust idiom; record this in the cross-plan Surprises so EP-5
   inherits it.

2. For commands that depend on environment that the harness cannot
   provide (in this case: a Kitty-graphics-capable terminal), validate
   the *output shape* with `cat -A` and treat the visual confirmation
   as a separate user-driven step. EP-5's `kanji show` validation
   should follow the same approach: assert the textual stroke output
   programmatically, document the image step, and ask the user to
   confirm visually.

3. EP-5 will compose `detectImageCapabilityWithOverride <no-images>`
   with `displaySvg cap label svgPath` after printing the textual
   stroke order. The interfaces line up — no adapter layer needed.


## Context and Orientation

This plan assumes EP-1 (`docs/plans/1-establish-nihongo-cli-foundations.md`) is
complete. It does *not* depend on EP-2 (KanjiVG submodule) or EP-3 (parser): the
image module operates on any SVG file path.

Repository layout you can assume after EP-1:

    nihongo-cli/
      nihongo-cli.cabal
      app/Main.hs
      help/about.md, help/width-demo.md
      src/Nihongo/Cli.hs
      src/Nihongo/Cli/{Version,Stdin,Width,Help,Completions}.hs
      src/Nihongo/Pretty.hs

This plan adds `nihongo-cli/src/Nihongo/Terminal/Image.hs` and a temporary debug
subcommand under `nihongo-cli/src/Nihongo/Cli/Commands/ImageDebug.hs`.

Definitions of terms used below:

- *Kitty graphics protocol*: a wire protocol where a terminal emulator reads an
  escape sequence of the form `\x1b_G<key>=<value>,...;<payload>\x1b\\` and renders
  the payload (or the file referenced by it) inline. Kitty (the original), WezTerm,
  and Ghostty all implement it. The protocol's "transmission medium" `t=f` means
  "the payload is a base64-encoded absolute file path; you, the terminal, read the
  file." That avoids putting binary image bytes through stdout, which is brittle.

- *tmux DCS passthrough*: tmux normally swallows escape sequences it doesn't
  understand. Setting `set -g allow-passthrough on` (or running tmux 3.3+ which
  enables it conditionally) tells tmux to forward DCS-wrapped escape sequences to
  the outer terminal. The wire format is `\x1bP tmux ; <inner-escape-with-each-ESC-doubled> \x1b\\`,
  where every `\x1b` byte inside the inner escape is doubled.

- *XDG cache home*: per the XDG Base Directory spec, the user's cache root is
  `$XDG_CACHE_HOME` if set, otherwise `~/.cache`.

- *capability detection*: the act of guessing whether the terminal we are talking
  to is Kitty-graphics-capable, by reading environment variables (`KITTY_WINDOW_ID`,
  `TERM`, `TERM_PROGRAM`, `TMUX`) and asking tmux about its outer environment when
  inside it.


### kizamu Image module reference

`/Users/shinzui/Keikaku/bokuno/kizamu-project/kizamu/src/Kizamu/Media.hs` is the
canonical implementation of the same pattern in a sibling project by the same author.
Read it for orientation; this plan adapts it. The cabal file at
`/Users/shinzui/Keikaku/bokuno/kizamu-project/kizamu/kizamu.cabal` shows the
deps used (only `bytestring`, `base64-bytestring`, `process`, `directory`,
`filepath`, `text` — no graphics libraries).

Key functions in `kizamu` to mirror:

- `data ImageCapability = KittyGraphics | NoImageSupport`
- `detectImageCapability :: IO ImageCapability` — uses env vars + tmux probe.
- `displayImage :: FilePath -> IO ()` — emits the Kitty escape with `a=T,f=100,t=f,r=8`,
  then 8 newlines so the cursor moves past the image. Wraps in tmux DCS when `TMUX`
  is set. `hFlush stdout` after emit.
- `tmuxEscape :: String -> String` — doubles every `\x1b` for tmux passthrough.
- `tmuxShowEnv :: Text -> IO (Maybe Text)` — runs `tmux show-environment -g <var>`
  and parses the result, swallowing IOError if tmux is missing.

`kizamu` does not rasterise SVGs; we add that step.


## Plan of Work

Four milestones.


### Milestone A — Capability detection

After this milestone the module exposes `ImageCapability` and `detectImageCapability`.

Add `process ^>= 1.6` and `unix ^>= 2.8` to `nihongo-cli/nihongo-cli.cabal`'s library
`build-depends` (`unix` is already a transitive dependency but list it explicitly so
intent is clear). `directory`, `filepath`, `bytestring`, `text` are present from
EP-1.

Create `nihongo-cli/src/Nihongo/Terminal/Image.hs` with the capability detection
section (the rest of the module fills in over later milestones):

    module Nihongo.Terminal.Image
      ( ImageCapability (..)
      , detectImageCapability
      , detectImageCapabilityWithOverride
      ) where

    import Control.Exception (IOException, try)
    import qualified Data.Text as Text
    import System.Environment (lookupEnv)
    import System.Process (readProcess)

    import Nihongo.Prelude

    data ImageCapability
      = KittyGraphics
      | NoImageSupport
      deriving stock (Eq, Show)

    -- | Decide whether the current terminal supports Kitty graphics, optionally
    --   short-circuiting to NoImageSupport when the caller has passed --no-images.
    detectImageCapabilityWithOverride :: Bool -> IO ImageCapability
    detectImageCapabilityWithOverride True  = pure NoImageSupport
    detectImageCapabilityWithOverride False = detectImageCapability

    detectImageCapability :: IO ImageCapability
    detectImageCapability = do
      mKitty <- lookupEnv "KITTY_WINDOW_ID"
      mTerm  <- lookupEnv "TERM"
      mProg  <- lookupEnv "TERM_PROGRAM"
      mTmux  <- lookupEnv "TMUX"
      let directHit =
               isJust mKitty
            || mTerm == Just "xterm-kitty"
            || mProg == Just "WezTerm"
            || mProg == Just "ghostty"
      if directHit
        then pure KittyGraphics
        else case mTmux of
          Nothing -> pure NoImageSupport
          Just _  -> do
            outerProg <- tmuxShowEnv "TERM_PROGRAM"
            pure $ if outerProg `elem` [Just "WezTerm", Just "ghostty"]
                     then KittyGraphics
                     else NoImageSupport
      where
        isJust = maybe False (const True)

    -- | Run `tmux show-environment -g <var>` and pull the value out. Swallows
    --   IOError so we still work when tmux is not installed.
    tmuxShowEnv :: Text -> IO (Maybe Text)
    tmuxShowEnv var = do
      result <- try (readProcess "tmux"
                       ["show-environment", "-g", Text.unpack var] "")
                :: IO (Either IOException String)
      pure $ case result of
        Left _      -> Nothing
        Right out   -> parseLine out
      where
        prefix = var <> "="
        parseLine s =
          case dropWhile (not . Text.isPrefixOf prefix) (Text.lines (Text.pack s)) of
            (l:_) -> Just (Text.drop (Text.length prefix) l)
            []    -> Nothing

Add `Nihongo.Terminal.Image` to `nihongo-cli/nihongo-cli.cabal`'s library
`exposed-modules`.

Acceptance: `cabal build all` succeeds. In a Kitty terminal,

    cabal repl nihongo-cli
    >>> import Nihongo.Terminal.Image
    >>> detectImageCapability
    KittyGraphics

In a non-Kitty terminal (e.g. macOS Terminal.app),

    >>> detectImageCapability
    NoImageSupport


### Milestone B — Kitty emitter and tmux passthrough

After this milestone the module exposes `displayImage`, which writes a Kitty graphics
escape sequence (or its tmux-wrapped equivalent) to stdout for a given absolute PNG
path.

Add `base64-bytestring ^>= 1.2` to `nihongo-cli/nihongo-cli.cabal`'s library
`build-depends`.

Append to `nihongo-cli/src/Nihongo/Terminal/Image.hs`:

    -- | Number of terminal rows the rendered image will occupy. Tuned for
    --   stroke-order images — taller than kizamu's 8-row default to make
    --   detail readable.
    imageRows :: Int
    imageRows = 12

    -- | Display a PNG file at an absolute path using the Kitty graphics
    --   protocol. The terminal reads the file itself (t=f) so we do not stream
    --   bytes through stdout. Caller is responsible for flushing/positioning.
    displayImage :: FilePath -> IO ()
    displayImage absPath = do
      isInTmux <- maybe False (const True) <$> lookupEnv "TMUX"
      let payload = Base64.encode (BS8.pack absPath)
          inner   =
            "\ESC_Ga=T,f=100,t=f,r=" <> BS8.pack (show imageRows) <> ";"
              <> payload <> "\ESC\\"
          escaped =
            if isInTmux
              then BS8.pack "\ESCPtmux;"
                <> tmuxDouble inner
                <> BS8.pack "\ESC\\"
              else inner
      BS8.hPut System.IO.stdout escaped
      -- Push the cursor below the image.
      replicateM_ imageRows (BS8.hPut System.IO.stdout "\n")
      System.IO.hFlush System.IO.stdout

    -- | Double every ESC byte to escape it through tmux's DCS passthrough.
    tmuxDouble :: ByteString -> ByteString
    tmuxDouble = BS8.concatMap (\c -> if c == '\ESC' then "\ESC\ESC" else BS8.singleton c)

You will need imports:

    import Control.Monad (replicateM_)
    import qualified Data.ByteString.Base64 as Base64
    import Data.ByteString (ByteString)
    import qualified Data.ByteString.Char8 as BS8
    import qualified System.IO as IO

(adjust the qualified `IO` references in the previous snippet accordingly).

Acceptance: in Kitty,

    >>> import Nihongo.Terminal.Image
    >>> displayImage "/Users/shinzui/Keikaku/hub/kanjivg/kanji/06f22.svg"

prints garbage (because it is an SVG, not a PNG, and `f=100` means "PNG"). That's
expected and is what the next milestone fixes by rasterising first. To exercise just
this milestone independently, use any PNG you have on disk. The successful behaviour
is "an inline image appears."


### Milestone C — SVG → PNG rasterisation with cache

After this milestone the module exposes `ensurePng`, which takes an SVG file path
and returns a path to an equivalent PNG, rasterising and caching as needed.

Add `cryptohash-sha256 ^>= 0.11` to `nihongo-cli/nihongo-cli.cabal`'s library
`build-depends`. (`directory` and `filepath` are already pulled in transitively from
`nihongo-core`; list them explicitly here for clarity.)

Append to `nihongo-cli/src/Nihongo/Terminal/Image.hs`:

    -- | Resolve <XDG_CACHE_HOME or ~/.cache>/nihongo/strokes/ and ensure it
    --   exists. Returns the directory path.
    cacheDir :: IO FilePath
    cacheDir = do
      mXdg <- lookupEnv "XDG_CACHE_HOME"
      home <- getHomeDirectory
      let root = case mXdg of
                   Just p  | not (null p) -> p
                   _                       -> home </> ".cache"
          dir  = root </> "nihongo" </> "strokes"
      createDirectoryIfMissing True dir
      pure dir

    -- | Given an SVG file path, return the path to a cached PNG of it. If the
    --   PNG does not exist (cache miss), rasterise via `rsvg-convert`. The cache
    --   key is the SHA-256 of the SVG file contents.
    ensurePng :: FilePath -> IO (Either Text FilePath)
    ensurePng svgPath = do
      svgBytes <- BS.readFile svgPath
      let digest = SHA256.hash svgBytes
          hex    = Text.pack (concatMap (printf "%02x") (BS.unpack digest))
      dir <- cacheDir
      let pngPath = dir </> Text.unpack hex <.> "png"
      cached <- doesFileExist pngPath
      if cached
        then pure (Right pngPath)
        else rasterise svgPath pngPath

    rasterise :: FilePath -> FilePath -> IO (Either Text FilePath)
    rasterise svgPath pngPath = do
      result <- try (readProcessWithExitCode
                       "rsvg-convert"
                       ["--format=png", "--output", pngPath, svgPath]
                       "")
                :: IO (Either IOException (ExitCode, String, String))
      case result of
        Left e -> pure (Left ("rsvg-convert not found: " <> Text.pack (show e)))
        Right (ExitSuccess, _, _)   -> pure (Right pngPath)
        Right (ExitFailure n, _, e) ->
          pure (Left ("rsvg-convert exit " <> Text.pack (show n) <> ": " <> Text.pack e))

You will need imports:

    import Control.Exception (try, IOException)
    import qualified Crypto.Hash.SHA256 as SHA256
    import qualified Data.ByteString as BS
    import System.Directory (createDirectoryIfMissing, doesFileExist, getHomeDirectory)
    import System.Exit (ExitCode (..))
    import System.FilePath ((</>), (<.>))
    import System.Process (readProcessWithExitCode)
    import Text.Printf (printf)

The `printf "%02x"` use produces a hex byte; over the 32-byte SHA-256 digest it
yields a 64-character lowercase hex filename (e.g.
`b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9.png`).

Acceptance:

    >>> ensurePng "data/kanjivg/kanji/06f22.svg"
    Right "/Users/shinzui/.cache/nihongo/strokes/<sha>.png"

A second call with the same file is instantaneous (no `rsvg-convert` invocation).
Verify by `ls ~/.cache/nihongo/strokes/`.


### Milestone D — `displaySvg` orchestration and debug subcommand

After this milestone the module exposes `displaySvg`, the function EP-5 will call,
and a temporary `image-debug-render` subcommand exercises it end to end.

Append to `nihongo-cli/src/Nihongo/Terminal/Image.hs`:

    -- | High-level entry point. Given a capability decision, a label (used for
    --   the fallback placeholder), and an SVG file path, do the right thing:
    --   under KittyGraphics, rasterise + display; otherwise print a dim
    --   `[Image: <label>]` placeholder.
    displaySvg :: ImageCapability -> Text -> FilePath -> IO ()
    displaySvg NoImageSupport label _ =
      TIO.putStrLn (Pretty.dim ("[Image: " <> label <> "]"))
    displaySvg KittyGraphics label svgPath = do
      ensured <- ensurePng svgPath
      case ensured of
        Left err -> do
          TIO.hPutStrLn IO.stderr ("warning: " <> err)
          TIO.putStrLn (Pretty.dim ("[Image: " <> label <> "]"))
        Right png -> displayImage png

You will need imports:

    import qualified Data.Text.IO as TIO
    import qualified Nihongo.Pretty as Pretty

Add `Nihongo.Terminal.Image.displaySvg` and `ImageCapability(..)`,
`detectImageCapability`, `detectImageCapabilityWithOverride`, `displaySvg` to the
module's export list.

Now the temporary debug subcommand. Create
`nihongo-cli/src/Nihongo/Cli/Commands/ImageDebug.hs`:

    module Nihongo.Cli.Commands.ImageDebug
      ( ImageDebugCommand (..)
      , imageDebugParser
      , runImageDebug
      ) where

    import qualified Data.Text as Text
    import Options.Applicative
        ( Parser
        , argument
        , help
        , long
        , metavar
        , str
        , switch
        )

    import Nihongo.Terminal.Image
        ( detectImageCapabilityWithOverride
        , displaySvg
        )
    import Nihongo.Prelude

    data ImageDebugCommand = ImageDebugCommand
      { idcSvgPath  :: FilePath
      , idcNoImages :: Bool
      }
      deriving stock (Show, Eq)

    imageDebugParser :: Parser ImageDebugCommand
    imageDebugParser =
      ImageDebugCommand
        <$> argument str (metavar "SVG_PATH" <> help "Path to a KanjiVG SVG file")
        <*> switch (long "no-images" <> help "Force the placeholder fallback")

    runImageDebug :: ImageDebugCommand -> IO ()
    runImageDebug (ImageDebugCommand path noImages) = do
      cap <- detectImageCapabilityWithOverride noImages
      displaySvg cap (Text.pack ("@" <> path)) path

Wire it into `Nihongo.Cli` like the EP-2 debug command. Add `internal` so it does
not appear in `nihongo --help`. Note for EP-5: remove this command and its module
once `kanji show` lands.

Acceptance: see Validation and Acceptance.


## Concrete Steps

Run from the repo root.

Milestone A:

    # Edit nihongo-cli/nihongo-cli.cabal: add `process`, `unix` deps; add Nihongo.Terminal.Image to exposed-modules.
    # Create the module with capability detection only.
    cabal build all
    # Inside Kitty:
    cabal repl nihongo-cli
    >>> import Nihongo.Terminal.Image
    >>> detectImageCapability

Milestone B:

    # Add base64-bytestring dep. Append the emitter sections.
    cabal build all
    # In Kitty: ensure you have any PNG handy; call displayImage with its absolute path.

Milestone C:

    # Add cryptohash-sha256 dep. Append the rasterisation sections.
    cabal build all
    # In repl:
    >>> import Nihongo.Terminal.Image
    >>> ensurePng "data/kanjivg/kanji/06f22.svg"

Milestone D:

    # Append displaySvg. Create the debug command. Wire into Nihongo.Cli.
    cabal build all
    # Inside Kitty:
    cabal run nihongo -- image-debug-render data/kanjivg/kanji/06f22.svg
    # Outside Kitty (or with --no-images):
    cabal run nihongo -- image-debug-render data/kanjivg/kanji/06f22.svg --no-images
    # Inside tmux inside Kitty:
    tmux new -s test \; send-keys "cabal run nihongo -- image-debug-render data/kanjivg/kanji/06f22.svg" Enter


## Validation and Acceptance

In Kitty (or WezTerm, or Ghostty): `cabal run nihongo -- image-debug-render
data/kanjivg/kanji/06f22.svg` displays an inline image of 漢 occupying ~12 terminal
rows, and the cursor lands on the row below the image. A second invocation is
instantaneous (cache hit). `ls ~/.cache/nihongo/strokes/` shows a `<sha256>.png`
file.

In a non-Kitty terminal (or with `--no-images`): the same command prints a single
dimmed line `[Image: @data/kanjivg/kanji/06f22.svg]` and exits zero. No image-related
escape sequences are written.

Inside tmux running in a Kitty terminal: with `set-option -g allow-passthrough on`
in `~/.tmux.conf`, the same image renders. Without passthrough, the user sees a
garbled escape sequence on screen — this is a tmux configuration issue, not a bug
in our code; document it in the help topic added by EP-5.

If `rsvg-convert` is missing on `PATH`, `displaySvg KittyGraphics ...` prints a
warning to stderr (`warning: rsvg-convert not found: ...`) and falls back to the
placeholder. To verify, run

    PATH=/usr/bin cabal run nihongo -- image-debug-render data/kanjivg/kanji/06f22.svg

(stripping the Nix shell from `PATH`); the program does not crash.


## Idempotence and Recovery

`ensurePng` is idempotent: a cache hit returns the same path; a cache miss
rasterises and then any subsequent call hits. The cache directory is created with
`createDirectoryIfMissing True`. To force re-rasterisation, `rm
~/.cache/nihongo/strokes/<sha>.png`.

`displayImage` writes raw bytes to stdout; running it twice prints two images. There
is no shared state to corrupt.

`detectImageCapability` is read-only.

If a corrupted PNG slips into the cache (e.g., `rsvg-convert` was killed mid-write),
delete it manually. We do not currently validate cache contents — a future
enhancement could verify the PNG header before trusting the cache.


## Interfaces and Dependencies

Cabal dependencies added to `nihongo-cli/nihongo-cli.cabal` library:

- `process ^>= 1.6` — to run `rsvg-convert` and `tmux`.
- `unix ^>= 2.8` — for the `System.IO`/handle integrations under POSIX.
- `base64-bytestring ^>= 1.2` — to base64-encode the file path in the Kitty
  payload.
- `cryptohash-sha256 ^>= 0.11` — to compute the SVG content hash for the cache key.
- `bytestring ^>= 0.12` — already present after EP-1; restated for clarity.

System tools required (provided by `flake.nix` after EP-1):

- `rsvg-convert` from `librsvg`. The module will fall back gracefully if absent.
- `tmux` (optional). Used only inside tmux for capability detection; absence is
  handled.

Exposed modules added to `nihongo-cli/nihongo-cli.cabal`:

- `Nihongo.Terminal.Image`.
- `Nihongo.Cli.Commands.ImageDebug` (temporary; removed by EP-5).

Public APIs subsequent ExecPlans rely on:

- `Nihongo.Terminal.Image.ImageCapability` (`KittyGraphics | NoImageSupport`).
- `Nihongo.Terminal.Image.detectImageCapability :: IO ImageCapability`.
- `Nihongo.Terminal.Image.detectImageCapabilityWithOverride :: Bool -> IO ImageCapability`
  (the `Bool` is "user passed --no-images").
- `Nihongo.Terminal.Image.displaySvg :: ImageCapability -> Text -> FilePath -> IO ()`.

EP-5 will:

1. Declare a `--no-images` flag in its `kanji show` parser (under the "Image" option
   group), of type `Bool`.
2. Call `detectImageCapabilityWithOverride <no-images-flag>` once at the start of
   `runShow`.
3. Call `displaySvg cap (Text.pack [c]) svgPath` after printing the textual stroke
   order.

Files added by this plan:

    nihongo-cli/src/Nihongo/Terminal/Image.hs
    nihongo-cli/src/Nihongo/Cli/Commands/ImageDebug.hs

Files whose ownership transfers to a later plan:

- `nihongo-cli/src/Nihongo/Cli/Commands/ImageDebug.hs` — EP-5 deletes this and the
  registration in `Nihongo.Cli` once `kanji show` lands. Record the deletion in
  EP-5's Decision Log.
