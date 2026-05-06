---
id: 8
slug: evaluate-file-embedding-the-kanjivg-svg-corpus-into-the-nihongo-binary
title: "Evaluate file-embedding the KanjiVG SVG corpus into the nihongo binary"
kind: exec-plan
created_at: 2026-05-06T05:01:40Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
---

# Evaluate file-embedding the KanjiVG SVG corpus into the nihongo binary

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan answers a single design question: **should the `nihongo` binary embed the
KanjiVG SVG corpus inside itself (via the `file-embed` Template Haskell library)
instead of reading the SVGs from the on-disk submodule at `data/kanjivg/`?**

The motivation for asking is real. Today, `nihongo kanji show 漢` and
`nihongo kanji png 漢` only work when the runtime working directory contains a
populated `data/kanjivg/kanji/<5-hex>.svg` corpus, *or* the user has set
`NIHONGO_KANJIVG_DIR`, *or* they passed `--kanjivg-dir PATH`. That is fine when
running from inside a checkout under `nix develop`, but a user who installs the
binary somewhere on their `PATH` and runs `nihongo kanji png 漢` from
`~/Documents/` gets the error message defined in
`Nihongo.Kanji.KanjiVg.defaultKanjiVgRoot` ("Could not find the KanjiVG corpus.
…"). Embedding the SVGs into the binary would make `nihongo` runnable from
anywhere, with no submodule and no env var, at the cost of a much larger binary
and a much slower compile.

What "done" looks like for this plan is *not* a refactor, and not necessarily a
shipping feature. It is a recorded, evidence-backed decision in the Decision Log
below — yes, no, or "yes for a subset" — together with the measurements that
support it, and one of three concrete follow-ups depending on which way the
decision goes:

- **If the answer is "no, keep the submodule on disk"**: this plan ships a small
  quality-of-life fix to the corpus-not-found error message in
  `Nihongo.Kanji.KanjiVg.defaultKanjiVgRoot` (file:
  `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`) so installed-binary users see a
  clearer remediation hint than today's "run `git submodule update --init …`",
  and writes the negative decision into the Decision Log so this question does
  not get re-litigated by the next contributor without new information.

- **If the answer is "yes, embed the full corpus"**: this plan lands a new module
  `Nihongo.Kanji.KanjiVg.Embedded` in `nihongo-cli` (path:
  `nihongo-cli/src/Nihongo/Kanji/KanjiVg/Embedded.hs`) that exposes a pure
  function `embeddedSvgBytes :: Kanji -> Maybe ByteString`, plus a thin wiring
  change in `Nihongo.Kanji.Png.kanjiPngPath` and
  `Nihongo.Cli.Commands.Kanji.Show.runShow` to fall back to embedded bytes when
  no on-disk root is found. The `--kanjivg-dir` and `NIHONGO_KANJIVG_DIR`
  overrides keep working and *win* over the embedded copy, so power users can
  still point at a newer KanjiVG release.

- **If the answer is "yes, but only a curated subset"** (e.g. the 2,136 jōyō
  kanji): this plan lands the same `Embedded` module but with a build-time
  filter, and documents the included codepoints in
  `nihongo-cli/help/kanji-png.md` and `nihongo-cli/help/kanji-show.md`.

You will know this plan is complete when (a) the Decision Log carries a single
unambiguous decision dated and signed with rationale, (b) the Surprises &
Discoveries section contains at least one short measurement transcript per
prototype milestone (B, C, D below), and (c) the chosen follow-up has been
implemented and verified by the matching invocation in *Validation and
Acceptance*.

The plan deliberately uses **prototyping milestones** (per the ExecPlan
specification's "Prototyping and Parallel Implementations" guidance — see
`.claude/skills/exec-plan/PLANS.md`). Milestones B, C, and D are explicitly
spike-style: they exist to gather measurement evidence on a throwaway branch and
then be discarded or promoted. Only Milestone E, after the decision, lands
non-throwaway code.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone A: Capture baseline measurements (binary size, build wall-clock time, runtime memory of `kanji png`) on `master` *as of the start of this plan* and paste them into Surprises & Discoveries. No code change.
- [ ] Milestone B: Spike — full-corpus `embedDir`. Implement `Nihongo.Kanji.KanjiVg.Embedded` on a throwaway branch (`spike/ep8-embed-full`) that uses `Data.FileEmbed.embedDir "data/kanjivg/kanji"` and exposes `embeddedSvgBytes`. Measure compile time, peak GHC RSS, binary size, and wall time of `nihongo kanji png 漢` against a wiped cache. Paste evidence into Surprises & Discoveries.
- [ ] Milestone C: Spike — jōyō-subset `embedFile`. On branch `spike/ep8-embed-joyou`, implement the same module but with a hand-curated list of jōyō codepoints (2,136 entries; concrete source named in *Concrete Steps* below). Measure the same axes as Milestone B. Paste evidence.
- [ ] Milestone D: Spike — non-embedding alternatives. Sketch (no code merge needed) what cabal `data-files` and a runtime-download path would look like, and write a short prose comparison into Surprises & Discoveries.
- [ ] Milestone E: Decision and follow-up. Write a single dated decision in the Decision Log selecting one of {keep submodule + better error, embed full, embed subset}. Then land the matching follow-up code. Mark the spike branches as "discard" in the Decision Log; do *not* merge them.
- [ ] Milestone F: Verification. Run every invocation in *Validation and Acceptance* applicable to the chosen follow-up and observe the documented output.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

Pre-flight observations gathered while writing this plan (2026-05-06):

- **The KanjiVG corpus on `master` is 75 MB across 11,661 files.** Measured by
  `du -sh data/kanjivg/kanji` (75M apparent) and `du -sk data/kanjivg/kanji`
  (77,100 KB on disk). The directory contains 6,702 plain `<5-hex>.svg` files
  (one per CJK codepoint covered) and 4,959 variant files
  (`<5-hex>-Kaisho.svg`, `<5-hex>-VtLst.svg`, etc.). The current
  `Nihongo.Kanji.KanjiVg.findStrokeSvg` only ever asks for the plain form
  (`<root>/kanji/<hex>.svg`), so the variant files are dead weight from the CLI's
  perspective regardless of which option is chosen — calling that out so the
  spike milestones do not embed them by accident.

  Evidence:

      $ /usr/bin/du -sh data/kanjivg/kanji
       75M    data/kanjivg/kanji
      $ ls data/kanjivg/kanji | wc -l
         11661
      $ find data/kanjivg/kanji -name '*.svg' -not -name '*-*' | wc -l
          6702
      $ find data/kanjivg/kanji -name '*-*.svg' | wc -l
          4959

- **`file-embed` is already in `nihongo-cli`'s `build-depends`** (constraint
  `file-embed ^>=0.0.16`, line 63 of `nihongo-cli/nihongo-cli.cabal`). Today it
  embeds four small markdown help topics under `nihongo-cli/help/*.md` via
  `Data.FileEmbed.embedStringFile` in `Nihongo.Cli.Help`. The header comment of
  that module already documents a known cabal-rebuild gotcha worth
  remembering for the spikes:

      Topics live under nihongo-cli/help/<name>.md and are compiled into the
      binary at build time via `Data.FileEmbed.embedStringFile`. Note: cabal
      does NOT recognise embedded file changes for relinking — after editing
      a topic you must `touch` this module or `cabal clean && cabal build all`
      to force a rebuild.

  Implication for this plan: any prototype that embeds the corpus must
  remember to `cabal clean` before measurement to avoid being misled by stale
  object files. Add `touch nihongo-cli/src/Nihongo/Kanji/KanjiVg/Embedded.hs`
  to every spike rebuild loop.

(More entries will be added as Milestones A–D run.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Frame this as a spike-driven design plan rather than implementing one
  approach up front. Milestones B and C are explicitly throwaway prototypes;
  Milestone E lands the chosen path.
  Rationale: The cost difference between "embed" and "don't embed" is on the
  order of 75 MB of binary and several minutes of build time, and the cost of
  building either prototype is small. Picking by intuition risks regret either
  way; picking by measurement is cheap.
  Date: 2026-05-06.

- Decision: Variants (`<hex>-Kaisho.svg`, `<hex>-VtLst.svg`, etc., 4,959 files
  totalling roughly 30 MB) are *out of scope* for any embedding milestone.
  Rationale: `Nihongo.Kanji.KanjiVg.findStrokeSvg` only asks for the plain
  `<root>/kanji/<hex>.svg` form; nothing in the current codebase reaches the
  variant files. Embedding them would inflate the binary for no behavioural
  benefit. If a future feature wants stylistic variants, it can be planned
  separately and graded against the same yardstick this plan establishes.
  Date: 2026-05-06.

- Decision: The author of this plan's prior expectation, *before measurement*,
  is "do not embed the full corpus". Recording this so it is visible whether
  measurements confirm or upset the prior.
  Rationale: 75 MB is a large bump for a single-tool CLI binary; GHC TH compile
  time on 11,661 ByteString literals is widely reported to be punishing in
  HLS; the existing on-disk + content-addressed PNG cache already handles the
  expensive part (rasterisation) once per kanji per machine. The prior is
  *not* a conclusion — Milestone B exists precisely to falsify it if the
  numbers are surprisingly tame.
  Date: 2026-05-06.

(Milestone E will append the final decision here, dated, with rationale anchored
to the measurements collected in Surprises & Discoveries.)


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan assumes the repository state left by EP-1 through EP-7
(`docs/plans/1-establish-nihongo-cli-foundations.md` through
`docs/plans/7-add-kanji-png-subcommand-and-library-function-returning-a-cached-png-path-for-a-kanji.md`).
All seven are checked in on `master`. You do not need to read them; everything you
need to know about the runtime data flow is summarised here.

The repository is a Cabal multi-package project:

- `nihongo-core` (path `nihongo-core/`, cabal file `nihongo-core/nihongo-core.cabal`)
  — pure-data, IO-light primitives.
- `nihongo-cli` (path `nihongo-cli/`, cabal file `nihongo-cli/nihongo-cli.cabal`)
  — argument parsing, terminal IO, the `nihongo` executable. Built from
  `nihongo-cli/app/Main.hs`, which calls `Nihongo.Cli.runCli`.

A single `cabal.project` at the root ties them together. Both packages share
a `common common-options` cabal stanza setting `default-language: GHC2024`
and a long warning-flags list.

The KanjiVG corpus lives at `data/kanjivg/`, as a git submodule pinned to
upstream release `r20250816` by EP-2. Concretely:

    $ git submodule status
     bd13ffbcc9d85cb86ae98bbbf001d9069220b901 data/kanjivg (r20250816)
    $ cat .gitmodules
    [submodule "data/kanjivg"]
        path = data/kanjivg
        url = https://github.com/KanjiVG/kanjivg.git

The on-disk shape that matters: under `data/kanjivg/kanji/` there are 11,661
`.svg` files. The two name shapes are:

- `<lowercase-5-hex-codepoint>.svg` — one per CJK codepoint that KanjiVG covers
  (6,702 such files). Example: `06f22.svg` is 漢 (U+6F22). Average size around
  6.6 KB; the file `06f22.svg` is 4,535 bytes.
- `<lowercase-5-hex-codepoint>-<variant>.svg` — stylistic variants (Kaisho,
  semi-cursive, etc.). 4,959 such files. **Nothing in the repository reads these
  today** — `Nihongo.Kanji.KanjiVg.findStrokeSvg` only asks for the plain form.

The runtime data flow that this plan considers changing has three steps and two
existing consumers.

The three steps, each implemented today as IO that touches the filesystem:

1. **Resolve the corpus root.**
   `Nihongo.Kanji.KanjiVg.resolveKanjiVgRoot :: Maybe FilePath -> IO (Maybe KanjiVgRoot)`
   (file: `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`). Tries, in order: the
   explicit override, then the `NIHONGO_KANJIVG_DIR` env var, then
   `<cwd>/data/kanjivg`. Returns the first whose `kanji/` subdirectory exists.
   `KanjiVgRoot` is `newtype KanjiVgRoot { rootPath :: FilePath }`.

2. **Locate the per-kanji SVG.**
   `Nihongo.Kanji.KanjiVg.findStrokeSvg :: KanjiVgRoot -> Kanji -> IO (Maybe FilePath)`
   (same file). Computes `<root>/kanji/<5-hex>.svg`, `doesFileExist`s it,
   returns it (or `Nothing`).

3. **Consume the SVG bytes.** Two consumer modules read the bytes off disk
   themselves, given the path:
   - `Nihongo.Kanji.StrokeOrder.parseStrokeOrderFile :: FilePath -> IO (Either ParseError StrokeOrderInfo)`
     (file: `nihongo-core/src/Nihongo/Kanji/StrokeOrder.hs`). XML parser
     producing the data behind `nihongo kanji show`'s textual stroke list.
   - `Nihongo.Terminal.Image.ensurePng :: FilePath -> IO (Either Text FilePath)`
     (file: `nihongo-cli/src/Nihongo/Terminal/Image.hs`). SHA-256-hashes the
     SVG bytes (mixed with a `cacheVersion` constant `"v2:width=384"`),
     looks up the result under `<XDG_CACHE_HOME or ~/.cache>/nihongo/strokes/<sha>.png`,
     and on a miss shells out to `rsvg-convert --format=png --width 384
     --keep-aspect-ratio --output <pngPath> <svgPath>`.

The two existing consumers (callers) of step 1+2:

- `Nihongo.Cli.Commands.Kanji.Show.runShow`
  (file: `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`, around line 118)
  resolves the root, calls `findStrokeSvg`, then both `parseStrokeOrderFile svg`
  and `displaySvg cap label svg` (which calls `ensurePng` internally).

- `Nihongo.Kanji.Png.kanjiPngPath`
  (file: `nihongo-cli/src/Nihongo/Kanji/Png.hs`, around line 60) resolves the
  root, calls `findStrokeSvg`, then `Image.ensurePng svgPath`.

Both consumers will be affected by any embedding decision because both
ultimately depend on either reading the SVG path off disk to read its bytes, or
on having the bytes some other way.

The `file-embed` library (currently `^>=0.0.16` in `nihongo-cli.cabal`) provides
two Template Haskell splices this plan cares about:

- `Data.FileEmbed.embedFile :: FilePath -> Q Exp` — reads one file at compile
  time and produces an expression of type `Data.ByteString.ByteString`. Used
  today by `Nihongo.Cli.Help` (one splice per markdown file).
- `Data.FileEmbed.embedDir  :: FilePath -> Q Exp` — recursively reads a
  directory at compile time and produces an expression of type
  `[(FilePath, ByteString)]`. The expression literally inlines every byte.

Both splices register their inputs as Template Haskell dependencies via
`addDependentFile`, but **cabal does not always trigger a rebuild when those
files change** without the source module being touched. The header of
`nihongo-cli/src/Nihongo/Cli/Help.hs` already documents this gotcha. The spike
milestones in this plan must compensate by `cabal clean` between measurements.

Definitions of terms used below (in plain language, no jargon left undefined):

- *Spike* / *prototype milestone*: a temporary code change made on a throwaway
  branch for the sole purpose of measuring something. The branch is discarded
  after the measurement is recorded; no spike code lands on `master`.
- *Embed*: at compile time, encode the bytes of a file (or many files) directly
  into the resulting binary, so the running program can access those bytes
  without touching the filesystem. Implemented here via `file-embed`.
- *jōyō kanji* (常用漢字): the official 2,136-character list of "regular-use"
  kanji designated by the Japanese Ministry of Education. The list is bounded
  and stable; it serves as a sensible "did the user need this character at all"
  cutoff.
- *XDG cache home*: per the XDG Base Directory specification, the user's
  per-user cache root is `$XDG_CACHE_HOME` if set, otherwise `~/.cache`.
- *cabal `data-files`*: a stanza in a `.cabal` file that names runtime data
  files cabal will install alongside the executable. They are accessed at
  runtime via the autogenerated `Paths_<pkg>.getDataFileName :: FilePath -> IO FilePath`.
  Mentioned here as one of the alternatives Milestone D weighs.
- *Conventional Commits*: the
  [Conventional Commits](https://www.conventionalcommits.org/) style required
  by `~/.claude/CLAUDE.md` for all commits in this repository — `feat:`, `fix:`,
  `docs:`, `refactor:`, `chore:`, etc., optionally with a scope, e.g.
  `chore(ep8): record baseline measurements`.


## Plan of Work

This plan has six milestones. The first four (A, B, C, D) gather evidence; E
records the decision and lands the matching follow-up; F is the verification
pass. Milestones B, C, and D are explicitly *spike* milestones — their work
happens on a throwaway branch and is discarded after measurements are
recorded, per the rationale in *Decision Log*.


### Milestone A — Baseline measurements

After this milestone the Surprises & Discoveries section contains a short
"baseline" entry recording the current state of the binary on `master` along
three axes: **binary size** (the executable that `cabal install` would ship),
**build wall-clock time from a clean state**, and **wall-clock time of
`nihongo kanji png 漢` against a wiped PNG cache**. No source files are
modified.

Capture the measurements with the exact commands in *Concrete Steps* below.
Paste each command and its top-line answer (e.g., `5.5M`, `1m32s`, `0.81s`)
into a new bullet under *Surprises & Discoveries* dated today. Keep the
phrasing factual: "On 2026-05-06 the stripped `nihongo` binary on `master`
is 5.5 MiB" — no commentary, just numbers.

This is the control case against which Milestones B and C are graded.

Acceptance for Milestone A: a `git diff` shows changes only to
`docs/plans/8-evaluate-file-embedding-the-kanjivg-svg-corpus-into-the-nihongo-binary.md`
(specifically a new bullet under *Surprises & Discoveries*), and the bullet
contains the three numbers and the commands that produced them.


### Milestone B — Spike: full-corpus `embedDir`

After this milestone you have a *throwaway* branch `spike/ep8-embed-full` on
which a new module `Nihongo.Kanji.KanjiVg.Embedded` has been added to
`nihongo-cli` and the same three baseline measurements re-run. The branch is
*not* merged — it exists solely to produce numbers.

Create `nihongo-cli/src/Nihongo/Kanji/KanjiVg/Embedded.hs` with this
spike-grade content (do not generalise; do not hand-tune the import list
beyond what GHC complains about):

    {-# LANGUAGE TemplateHaskell #-}

    -- | EP-8 SPIKE — DO NOT MERGE.
    --   Full-corpus file-embed of every plain `<5-hex>.svg` under
    --   data/kanjivg/kanji/. Used only to measure the cost of embedding.
    module Nihongo.Kanji.KanjiVg.Embedded
      ( embeddedSvgBytes
      , embeddedCount
      ) where

    import Data.ByteString (ByteString)
    import Data.FileEmbed (embedDir)
    import Data.Map.Strict qualified as Map
    import Data.Map.Strict (Map)
    import System.FilePath (splitExtension)

    import Nihongo.Kanji (Kanji, kanjiCodepointHex)
    import Nihongo.Prelude
    import Data.Text qualified as Text

    embedded :: Map String ByteString
    embedded =
      Map.fromList
        [ (base, bs)
        | (path, bs) <- $(embedDir "data/kanjivg/kanji")
        , let (base, ext) = splitExtension path
        , ext == ".svg"
        , '-' `notElem` base   -- skip variant files; we never read them
        ]

    embeddedCount :: Int
    embeddedCount = Map.size embedded

    embeddedSvgBytes :: Kanji -> Maybe ByteString
    embeddedSvgBytes k = Map.lookup (Text.unpack (kanjiCodepointHex k)) embedded

Add `Nihongo.Kanji.KanjiVg.Embedded` to the `library` stanza's
`exposed-modules` in `nihongo-cli/nihongo-cli.cabal`. Add `containers` to that
stanza's `build-depends` if it is not already present (it is not currently
declared in `nihongo-cli.cabal`; `nihongo-core` does declare it). Use the
constraint `containers ^>=0.7` to match `nihongo-core`'s declaration in
`nihongo-core/nihongo-core.cabal`.

**Cabal sdist plumbing — important.** `Data.FileEmbed.embedDir` reads files
from the source tree at compile time. Cabal does *not* automatically include
arbitrary tree files in an `sdist` tarball — only files declared in
`extra-source-files`, `data-files`, or `extra-doc-files`, plus modules listed
under each component. For the spike build to succeed *from the sdist*
(`cabal sdist && cd dist-newstyle/sdist/* && tar xf *.tar.gz && cabal build`)
the spike must also add a glob to `nihongo-cli/nihongo-cli.cabal`:

    extra-source-files:
      ../data/kanjivg/kanji/*.svg

(`extra-source-files` accepts globs from cabal-version 3.0 onward; the project
uses 3.4, so this is fine.) Without this line the sdist build will fail with
a Template Haskell error about a missing file the moment GHC evaluates the
splice. Verify the sdist round-trip explicitly as one of the spike
measurements — see *Concrete Steps*.

Wire the spike module's path resolver into both consumers, so the spike
actually exercises end-to-end. The wiring is intentionally minimal — write a
spike helper, do not refactor the production code:

In `nihongo-cli/src/Nihongo/Kanji/Png.hs`, before calling `Image.ensurePng`,
fall back to a temp-file containing the embedded bytes when `findStrokeSvg`
returns `Nothing`. The simplest spike form is:

    -- in kanjiPngPath, after `findStrokeSvg root kanji`:
    case mSvg of
      Just svgPath -> ... -- existing path
      Nothing -> case Embedded.embeddedSvgBytes kanji of
        Nothing -> pure (Left (KpeSvgMissing kanji))
        Just bytes -> do
          dir <- Image.cacheDir          -- requires exporting cacheDir
          let tmp = dir </> "ep8-spike.svg"
          BS.writeFile tmp bytes
          ensured <- Image.ensurePng tmp
          ...

(`Image.cacheDir` is currently un-exported. For this spike, add it to the
export list of `Nihongo.Terminal.Image`. Revert that export change when
discarding the branch.)

Once the spike compiles and runs, take measurements:

    # 1. Build wall-clock time from clean.
    cabal clean
    /usr/bin/time -p cabal build all 2>&1 | tail -3

    # 2. Stripped binary size.
    bin=$(cabal list-bin nihongo)
    cp "$bin" /tmp/nihongo-spike-full
    strip /tmp/nihongo-spike-full
    /usr/bin/du -h /tmp/nihongo-spike-full

    # 3. Cold-cache wall time of `kanji png 漢`.
    rm -rf ~/.cache/nihongo/strokes
    /usr/bin/time -p cabal run -v0 nihongo -- kanji png 漢 2>&1 | tail -3

    # 4. HLS responsiveness sanity check (subjective): open
    #    `nihongo-cli/src/Nihongo/Kanji/KanjiVg/Embedded.hs` in your editor
    #    and note whether HLS produces hover info within ~30 seconds, or
    #    appears to hang. Record "ok" / "slow (Ns)" / "hung".

Paste the output (including any GHC OOM, stack overflow, or "splice took N
seconds" diagnostics) into Surprises & Discoveries under a "Milestone B
spike" bullet.

Acceptance for Milestone B: the bullet exists, contains the four
measurements (build time, binary size, cold-cache wall time, HLS subjective
note), and the spike branch is left in place but **not merged into
`master`**.


### Milestone C — Spike: jōyō-subset embed

After this milestone you have a second throwaway branch
`spike/ep8-embed-joyou` carrying a variant of the Milestone B module that
only embeds the 2,136 jōyō codepoints, with the same measurements recorded.

Source the jōyō list as a single file in the spike branch, committed at
`nihongo-cli/data/joyou-codepoints.txt` for the spike's own
build-time-only consumption. Each line is a single hex codepoint without
`U+` prefix or `0x` prefix, e.g.:

    4e00
    4e01
    ...

If you do not have a curated list handy, derive one programmatically — the
official jōyō list is published by the Japanese Ministry of Education, but a
machine-readable transcription is in the public domain via the Unihan
database. A pragmatic shortcut for the spike (since "exact" jōyō membership
is not the point — the point is to measure ~2k vs ~6.7k):

    # Take the first 2136 plain SVGs alphabetically. NOT the real jōyō set,
    # but the same order of magnitude. Acceptable for a spike measurement;
    # call it out explicitly in Surprises & Discoveries.
    ls data/kanjivg/kanji \
      | grep -E '^[0-9a-f]{5}\.svg$' \
      | sort \
      | head -2136 \
      | sed 's/\.svg$//' \
      > nihongo-cli/data/joyou-codepoints.txt

Replace the `embedDir` body in `Nihongo.Kanji.KanjiVg.Embedded` with a
selective `embedFile` per line:

    {-# LANGUAGE TemplateHaskell #-}
    module Nihongo.Kanji.KanjiVg.Embedded ( embeddedSvgBytes, embeddedCount ) where

    import Data.ByteString (ByteString)
    import Data.FileEmbed (embedFile)
    import Data.Map.Strict qualified as Map
    import Data.Map.Strict (Map)
    import Language.Haskell.TH (runIO)
    import Language.Haskell.TH.Syntax (lift)

    import Nihongo.Kanji (Kanji, kanjiCodepointHex)
    import Nihongo.Prelude
    import qualified Data.Text as Text
    import qualified Data.ByteString as BS

    embedded :: Map String ByteString
    embedded = Map.fromList
      $(do
        codepoints <- runIO (lines <$> readFile "nihongo-cli/data/joyou-codepoints.txt")
        let pairs =
              [ [| ($(lift hex), $(embedFile ("data/kanjivg/kanji/" <> hex <> ".svg"))) |]
              | hex <- codepoints
              ]
        listE pairs)

    -- (rest unchanged from Milestone B)

Take the same four measurements (build time, binary size, cold-cache wall
time, HLS note) and paste them into a "Milestone C spike" bullet under
Surprises & Discoveries.

Acceptance for Milestone C: the bullet exists with all four measurements
and a one-line note explaining whether the codepoints chosen are the true
jōyō set or the alphabetical-shortcut set described above. Branch left in
place but **not merged**.


### Milestone D — Spike: non-embedding alternatives

After this milestone the Surprises & Discoveries section contains a short
prose comparison (no code merged) of four alternatives to file-embed,
evaluated on the same axes used for Milestones B and C.

The first two alternatives are *cabal-native* mechanisms for shipping data
files. They are mechanically distinct from `file-embed`:

1. **Cabal `data-files`.** Add the following to the `library` stanza of
   `nihongo-cli/nihongo-cli.cabal`:

        data-dir: ../data/kanjivg
        data-files: kanji/*.svg

   Then resolve a path at runtime via the autogenerated module:

        import Paths_nihongo_cli (getDataFileName)
        ...
        path <- getDataFileName ("kanji/" <> hex <> ".svg")

   Cabal copies the listed files into the package's installed `datadir`
   (under `cabal install --installdir=…` this lands beside the binary; the
   Nix derivation produces a similar layout under
   `$out/share/<pkg>-<ver>/`). Estimate without building: zero binary-size
   impact, zero compile-time impact, **but** the resulting binary is no
   longer self-contained — running it from a directory other than its
   install prefix relies on `Paths_*` having recorded the install path
   correctly, which works for `cabal install`-style workflows and Nix but
   does not work for "scp the binary somewhere and run it" workflows.
   Glob support in `data-files` requires `cabal-version: 3.0` or higher;
   the project is on 3.4, so `kanji/*.svg` is valid.

2. **Cabal `extra-source-files` *only* (no embedding).** This is the
   minimum-effort variant of the alternatives: declare

        extra-source-files:
          ../data/kanjivg/kanji/*.svg

   without using `file-embed` and without using `data-files`. The corpus
   becomes part of the source tarball produced by `cabal sdist`, so anyone
   who builds from the sdist gets a working tree. The corpus is *not*
   installed alongside the binary, so this option only helps source
   builders; it does not improve the installed-binary UX at all. Mention
   this for completeness; it is unlikely to be the chosen direction on
   its own merits but it pairs with options 1 and 4 below.

The remaining two alternatives are not cabal-native:

3. **First-run runtime fetch.** On the first call to `kanjiPngPath` or
   `runShow`, if no on-disk corpus is found, fetch a tarball from a known
   URL (e.g. the GitHub release asset for `r20250816`), unpack it under
   `<XDG_DATA_HOME or ~/.local/share>/nihongo/kanjivg/`, and proceed.
   Estimate: binary size impact (none), build impact (none), runtime impact
   (one-time multi-MB download on first use; requires network), code
   complexity (introduces an HTTP client dependency, an unpack step, error
   modes for offline use).

4. **Status quo with better error UX.** Improve the
   "could not find corpus" message in `Nihongo.Kanji.KanjiVg.defaultKanjiVgRoot`
   to suggest concrete remediations for the installed-binary case (e.g.,
   "set `NIHONGO_KANJIVG_DIR=/path/to/checkout` or run from a directory
   containing `data/kanjivg/kanji/`"). Also extend `resolveKanjiVgRoot` to
   search a fourth fallback path:
   `<XDG_DATA_HOME or ~/.local/share>/nihongo/kanjivg/`. Estimate: trivial
   code change, zero binary impact, zero build impact; preserves the
   existing override surface and adds one well-understood install location.

Write the comparison as a short paragraph per option, in
Surprises & Discoveries under a "Milestone D alternatives" bullet. Two to
five sentences each — enough to compare against the spike numbers, not a
full design.

Acceptance for Milestone D: the bullet exists and covers all four
alternatives.


### Milestone E — Decision and follow-up

After this milestone the Decision Log carries a single dated bullet stating
the chosen direction and pointing to the measurements that justify it; the
matching follow-up code is committed on `master`; the spike branches are
recorded as discardable.

Choose one of:

1. **Keep the submodule on disk; ship error-message and search-path
   improvements.** Commit a change to
   `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs` that:
   - Adds an XDG-data-home fallback to `resolveKanjiVgRoot` (between the
     env var step and the `<cwd>/data/kanjivg` step), looking for
     `<XDG_DATA_HOME or ~/.local/share>/nihongo/kanjivg`.
   - Rewrites the error string in `defaultKanjiVgRoot` to list all four
     candidates the resolver tries, in order, and to suggest the
     XDG-data-home install path as the recommended remediation for
     installed-binary users.
   - Updates `nihongo-cli/help/kanji-png.md` and
     `nihongo-cli/help/kanji-show.md`'s "Requirements" sections to mention
     the XDG-data-home install location.

2. **Embed the full corpus.** Promote the Milestone B spike module to
   non-spike status: rename the header comment to remove "SPIKE", remove the
   `cacheDir` re-export hack and instead read the embedded bytes through a
   small new helper, and add a fallback path in
   `Nihongo.Kanji.Png.kanjiPngPath` and
   `Nihongo.Cli.Commands.Kanji.Show.runShow` that uses
   `embeddedSvgBytes` when `findStrokeSvg` returns `Nothing`. The on-disk
   override paths still win, so users with a newer KanjiVG checkout
   continue to use it. Update the help topics to document the embedded
   corpus (release version baked in, how to override).

3. **Embed a curated subset.** Same as option 2, but with the curated
   codepoint list; document the included list (probably "all jōyō; outside
   that set, set `--kanjivg-dir` or `NIHONGO_KANJIVG_DIR`").

The decision text in the Decision Log must include:

- A one-sentence statement of the chosen option.
- A bullet list of the three baseline numbers from Milestone A and the
  matching numbers from each spike, so the cost can be read at a glance.
- One paragraph of rationale that explicitly cites at least one of the
  measurements.
- A line stating that branches `spike/ep8-embed-full` and
  `spike/ep8-embed-joyou` are now safe to delete.

Acceptance for Milestone E: the Decision Log entry exists and the chosen
follow-up code is committed (every commit carrying the trailers in
*Concrete Steps* below).


### Milestone F — Verification

After this milestone the chosen follow-up has been exercised end-to-end and
the result documented under Outcomes & Retrospective.

The exact invocations to run depend on which option E selected; see
*Validation and Acceptance*. Run them, confirm the documented behaviour,
and write a short Outcomes & Retrospective entry comparing the result
against the Purpose / Big Picture statement at the top of this plan.


## Concrete Steps

All commands run from the repository root
(`/Users/shinzui/Keikaku/bokuno/nihongo`) inside `nix develop` (so
`rsvg-convert`, `cabal`, and a matching GHC are on `PATH`). The
KanjiVG submodule must be initialised:

    git submodule update --init data/kanjivg

Verify that `data/kanjivg/kanji/` contains roughly 11,661 `.svg` files:

    ls data/kanjivg/kanji | wc -l    # expect 11661


### Milestone A — baseline measurements

    git switch master      # ensure we measure master, not a spike

    # 1. Clean build wall-clock time.
    cabal clean
    /usr/bin/time -p cabal build all 2>&1 | tail -5
    # Record the "real" line.

    # 2. Stripped binary size.
    bin=$(cabal list-bin nihongo)
    cp "$bin" /tmp/nihongo-baseline
    strip /tmp/nihongo-baseline
    /usr/bin/du -h /tmp/nihongo-baseline
    # Record the human-readable size (e.g. "5.5M").

    # 3. Cold-cache wall time of `kanji png 漢`.
    rm -rf ~/.cache/nihongo/strokes
    /usr/bin/time -p cabal run -v0 nihongo -- kanji png 漢 2>&1 | tail -5
    # Record both the "real" line and the printed PNG path.

Paste the three numbers into Surprises & Discoveries in a new bullet titled
"Milestone A baseline (YYYY-MM-DD)".

Commit the plan-file change with the trailers:

    git add docs/plans/8-*.md
    git commit -m "$(cat <<'EOF'
    chore(ep8): record baseline measurements

    ExecPlan: docs/plans/8-evaluate-file-embedding-the-kanjivg-svg-corpus-into-the-nihongo-binary.md
    Intention: intention_01kqxhfvpae3xv0dr9bnsxfdxs
    EOF
    )"


### Milestone B — full-corpus spike

    git switch -c spike/ep8-embed-full

    # Create the spike module per the body shown in *Plan of Work*.
    # Edit nihongo-cli/nihongo-cli.cabal:
    #   - add  Nihongo.Kanji.KanjiVg.Embedded  to exposed-modules
    #   - add  containers ^>=0.7  to build-depends
    #   - add  extra-source-files: ../data/kanjivg/kanji/*.svg
    # Edit Nihongo.Kanji.Png to wire the embedded fallback (per Plan of Work).
    # Add Image.cacheDir to the Nihongo.Terminal.Image export list.

    # 1. Clean build, capture time AND any GHC OOM/stack-overflow output.
    cabal clean
    /usr/bin/time -p cabal build all 2>&1 | tee /tmp/ep8-spike-full-build.log | tail -20
    # The full log goes into the plan-file bullet alongside the time.

    # 2. Stripped binary size.
    bin=$(cabal list-bin nihongo)
    cp "$bin" /tmp/nihongo-spike-full
    strip /tmp/nihongo-spike-full
    /usr/bin/du -h /tmp/nihongo-spike-full

    # 3. Cold-cache wall time.
    rm -rf ~/.cache/nihongo/strokes
    /usr/bin/time -p cabal run -v0 nihongo -- kanji png 漢 2>&1 | tail -5

    # 4. sdist round-trip — proves extra-source-files plumbing is right.
    cabal sdist nihongo-cli
    sdist=$(ls dist-newstyle/sdist/nihongo-cli-*.tar.gz | tail -1)
    work=$(mktemp -d)
    tar -xzf "$sdist" -C "$work"
    (cd "$work"/nihongo-cli-* && cabal build)
    # Expect a clean build. If GHC errors with "openBinaryFile: ... does not exist"
    # for an SVG path, the extra-source-files glob is wrong — fix it before
    # recording measurements.

    # 5. HLS subjective check (open the new module in your editor; observe).

Paste the five results into a Surprises & Discoveries bullet titled
"Milestone B spike (YYYY-MM-DD): full corpus".

Do **not** merge the branch. Push it (so a teammate can reproduce) but leave
`master` untouched:

    git push -u origin spike/ep8-embed-full


### Milestone C — jōyō-subset spike

    git switch master
    git switch -c spike/ep8-embed-joyou

    # Generate the codepoint list. If you already have a curated jōyō list,
    # use it; otherwise use the alphabetical-shortcut form documented in
    # Plan of Work and call it out explicitly in the measurement bullet.
    mkdir -p nihongo-cli/data
    ls data/kanjivg/kanji \
      | grep -E '^[0-9a-f]{5}\.svg$' \
      | sort \
      | head -2136 \
      | sed 's/\.svg$//' \
      > nihongo-cli/data/joyou-codepoints.txt
    wc -l nihongo-cli/data/joyou-codepoints.txt   # expect 2136

    # Replace the Embedded module body per the Milestone C variant in
    # Plan of Work. extra-source-files in the .cabal must list the SVGs;
    # since we are still embedding files under data/kanjivg/kanji, the
    # same glob from Milestone B is fine.

    cabal clean
    /usr/bin/time -p cabal build all 2>&1 | tee /tmp/ep8-spike-joyou-build.log | tail -20

    bin=$(cabal list-bin nihongo)
    cp "$bin" /tmp/nihongo-spike-joyou
    strip /tmp/nihongo-spike-joyou
    /usr/bin/du -h /tmp/nihongo-spike-joyou

    rm -rf ~/.cache/nihongo/strokes
    /usr/bin/time -p cabal run -v0 nihongo -- kanji png 漢 2>&1 | tail -5

    cabal sdist nihongo-cli && \
      sdist=$(ls dist-newstyle/sdist/nihongo-cli-*.tar.gz | tail -1) && \
      work=$(mktemp -d) && \
      tar -xzf "$sdist" -C "$work" && \
      (cd "$work"/nihongo-cli-* && cabal build)

Paste results into a Surprises & Discoveries bullet titled
"Milestone C spike (YYYY-MM-DD): jōyō subset".

    git push -u origin spike/ep8-embed-joyou
    git switch master


### Milestone D — alternatives comparison

No commands here beyond editing the plan file. Read the four alternatives in
*Plan of Work* and write a paragraph each into Surprises & Discoveries
under "Milestone D alternatives (YYYY-MM-DD)". Commit:

    git add docs/plans/8-*.md
    git commit -m "$(cat <<'EOF'
    docs(ep8): compare non-embedding alternatives

    ExecPlan: docs/plans/8-evaluate-file-embedding-the-kanjivg-svg-corpus-into-the-nihongo-binary.md
    Intention: intention_01kqxhfvpae3xv0dr9bnsxfdxs
    EOF
    )"


### Milestone E — decision and follow-up

Append the decision to the Decision Log per the template in *Plan of Work*.
Then implement the chosen follow-up.

If the decision is "keep submodule + better error UX", the concrete edits
are these and only these:

1. In `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`, extend `resolveKanjiVgRoot`
   to also try `<XDG_DATA_HOME or ~/.local/share>/nihongo/kanjivg` between the
   env-var step and the cwd step. Add a `getXdgDirectory` import from
   `System.Directory` (or compute by hand from `lookupEnv "XDG_DATA_HOME"`
   plus `getHomeDirectory` to match the style of
   `Nihongo.Terminal.Image.cacheDir`). Rewrite the `defaultKanjiVgRoot`
   error string to enumerate all four candidates and recommend the
   XDG-data-home install path.

2. In `nihongo-cli/help/kanji-png.md` and
   `nihongo-cli/help/kanji-show.md`, add a sentence under "Requirements"
   documenting the XDG-data-home install path
   (`~/.local/share/nihongo/kanjivg/`).

3. `touch nihongo-cli/src/Nihongo/Cli/Help.hs` so the embedded help topics
   pick up the new content.

4. `cabal build all` and run the verification invocations in
   *Validation and Acceptance*.

If the decision is "embed the full corpus" or "embed a subset", the
implementation reuses the spike module almost verbatim — but on `master`,
not on the spike branch. Cherry-pick the spike commits into a fresh branch
or just re-author the file with the "SPIKE — DO NOT MERGE" header removed
and the wiring change made directly to `Nihongo.Kanji.Png.kanjiPngPath` and
`Nihongo.Cli.Commands.Kanji.Show.runShow`.

Commit (split into reasonable Conventional Commits):

    git commit -m "$(cat <<'EOF'
    feat(<scope>): EP-8 — <one-line summary of the chosen follow-up>

    <body explaining what changed and why, citing the Decision Log.>

    ExecPlan: docs/plans/8-evaluate-file-embedding-the-kanjivg-svg-corpus-into-the-nihongo-binary.md
    Intention: intention_01kqxhfvpae3xv0dr9bnsxfdxs
    EOF
    )"


### Milestone F — verification

Run the invocations in *Validation and Acceptance* applicable to the chosen
option. Paste the transcripts into Outcomes & Retrospective.

Finally, delete the spike branches once the decision and follow-up are
recorded:

    git branch -D spike/ep8-embed-full   2>/dev/null || true
    git branch -D spike/ep8-embed-joyou  2>/dev/null || true
    git push origin --delete spike/ep8-embed-full   2>/dev/null || true
    git push origin --delete spike/ep8-embed-joyou  2>/dev/null || true


## Validation and Acceptance

Acceptance is split into "evidence acceptance" (Milestones A–D, common to
every outcome) and "follow-up acceptance" (Milestones E–F, depends on which
option was chosen).


### Evidence acceptance — independent of the final decision

After Milestone A, Surprises & Discoveries contains a "Milestone A baseline"
bullet listing three numbers: build wall-clock time on `master` from a clean
state, stripped binary size, and cold-cache wall time of `nihongo kanji png 漢`.

After Milestone B, the same bullet shape exists titled
"Milestone B spike: full corpus", with the additional fact that the sdist
round-trip (`cabal sdist` → unpack → `cabal build`) succeeded. If the round
trip failed, the spike is incomplete and Milestone B is not yet acceptable.

After Milestone C, the equivalent bullet exists titled
"Milestone C spike: jōyō subset".

After Milestone D, a "Milestone D alternatives" bullet contains four short
paragraphs (one per alternative described in *Plan of Work*).


### Follow-up acceptance — option 1: keep submodule + better error UX

After Milestone E, with the corpus *not* installed under
`~/.local/share/nihongo/kanjivg/` and *no* `data/kanjivg/` in the cwd:

    $ cd /tmp                                  # away from the repo
    $ cabal --project-dir=/Users/shinzui/Keikaku/bokuno/nihongo \
        run -v0 nihongo -- kanji png 漢
    Could not find the KanjiVG corpus. Tried, in order:
      1. --kanjivg-dir override
      2. NIHONGO_KANJIVG_DIR env var
      3. ~/.local/share/nihongo/kanjivg
      4. ./data/kanjivg
    Recommended: install the corpus under ~/.local/share/nihongo/kanjivg/,
    or set NIHONGO_KANJIVG_DIR to point at a KanjiVG checkout.
    $ echo $?
    1

(The exact wording is the implementer's choice; what matters is that all
four candidates appear in order and the XDG-data-home path is named.)

With the corpus symlinked into the new fallback:

    $ ln -s /Users/shinzui/Keikaku/bokuno/nihongo/data/kanjivg \
        ~/.local/share/nihongo/kanjivg
    $ cd /tmp
    $ cabal --project-dir=/Users/shinzui/Keikaku/bokuno/nihongo \
        run -v0 nihongo -- kanji png 漢
    /Users/shinzui/.cache/nihongo/strokes/<sha>.png
    $ echo $?
    0

The existing `--kanjivg-dir` and `NIHONGO_KANJIVG_DIR` paths still win when
set (verify by pointing them at a directory and observing that it is used
in preference to the XDG-data-home location — e.g., move the symlink target
elsewhere, set the env var to it, and confirm the printed PNG path matches a
cache entry derived from those bytes).

`nihongo help kanji-png` and `nihongo help kanji-show` mention the
XDG-data-home install path under "Requirements".


### Follow-up acceptance — option 2: embed the full corpus

After Milestone E:

    $ cd /tmp                                  # no submodule, no env vars
    $ unset NIHONGO_KANJIVG_DIR
    $ cabal --project-dir=/Users/shinzui/Keikaku/bokuno/nihongo \
        run -v0 nihongo -- kanji png 漢
    /Users/shinzui/.cache/nihongo/strokes/<sha>.png   # exit 0

The on-disk override still wins:

    $ cabal --project-dir=/Users/shinzui/Keikaku/bokuno/nihongo \
        run -v0 nihongo -- kanji png 漢 \
        --kanjivg-dir /Users/shinzui/Keikaku/bokuno/nihongo/data/kanjivg
    # Same path as above (cache is keyed by SVG bytes).

Pick a kanji that KanjiVG covers but the embedded set should also cover
(e.g. `一`, `日`, `本`):

    $ cabal --project-dir=… run -v0 nihongo -- kanji png 一
    /Users/shinzui/.cache/nihongo/strokes/<other-sha>.png   # exit 0

A kanji KanjiVG does not cover (CJK Extension B, e.g. U+2000B 𠀋) still
fails the same way it always did:

    $ cabal --project-dir=… run -v0 nihongo -- kanji png 𠀋
    KanjiVG has no entry for 𠀋
    # exit 1


### Follow-up acceptance — option 3: embed a curated subset

Same as option 2, with the added invariant that an outside-the-subset kanji
falls back through the on-disk path normally. If the subset is "jōyō only",
take a kanji that is in KanjiVG but not in jōyō (e.g. `龘`, U+9F98) and
confirm:

    $ unset NIHONGO_KANJIVG_DIR
    $ cd /tmp
    $ cabal --project-dir=… run -v0 nihongo -- kanji png 龘
    Could not find the KanjiVG corpus. … (same message as option 1)
    # exit 1

    $ cabal --project-dir=… run -v0 nihongo -- kanji png 龘 \
        --kanjivg-dir /Users/shinzui/Keikaku/bokuno/nihongo/data/kanjivg
    /Users/shinzui/.cache/nihongo/strokes/<sha>.png   # exit 0

The help topics (`kanji-png.md`, `kanji-show.md`) state which kanji are
embedded and how to handle the rest.


### Common regression checks

Whichever option lands, run:

    cabal build all                             # clean build, no warnings
    cabal run nihongo -- help                   # lists kanji-png, kanji-show
    cabal run nihongo -- kanji --help           # lists show, png
    cabal run nihongo -- kanji show 漢          # textual stroke list still renders
    cabal run nihongo -- kanji png 漢           # PNG path still printed


## Idempotence and Recovery

Every measurement step is idempotent: re-running `cabal clean && cabal build
all` from a fixed checkout produces the same binary, and re-running
`/usr/bin/time -p cabal run nihongo -- kanji png 漢` against an empty cache
produces the same wall-clock time within normal noise.

The spike branches are isolated by design. To abandon a spike at any time:

    git switch master
    git branch -D spike/ep8-embed-full   2>/dev/null
    git branch -D spike/ep8-embed-joyou  2>/dev/null

This is a no-op for `master` and discards only the throwaway work.

The only potentially destructive step in the entire plan is the "delete the
spike branches" cleanup at the end of Milestone F. It is safe because (a)
nothing on `master` ever depended on those branches, and (b) the
measurements they produced are recorded in the plan-file Surprises &
Discoveries section. If you want a paranoid safety net, push the spike
branches to the remote (`git push -u origin spike/ep8-embed-full`) before
the cleanup; the local delete still leaves the remote intact.

The XDG-data-home symlink used in option 1's verification is also safe to
remove at any time: `rm ~/.local/share/nihongo/kanjivg`. The directory will
not exist on a typical machine until you create it, so no other tool will
be affected.

If a `cabal sdist` round-trip fails during Milestone B or C, the cause is
almost always a missing entry in `extra-source-files`. Add the missing
glob to `nihongo-cli/nihongo-cli.cabal` and re-run; nothing else needs to
be cleaned up.

If the GHC compile in Milestone B fails with an out-of-memory error or a TH
"failed to evaluate splice" error, that is itself a measurement worth
recording. Note the error verbatim in Surprises & Discoveries; it is data
that informs the Decision Log. Do not work around it by reducing the
embedded set — that defeats the point of the spike. Move on to Milestone C
(which embeds fewer files and may therefore succeed).


## Interfaces and Dependencies

Cabal dependencies potentially added: depends on the chosen option.

- **Option 1 (status quo + UX fix)**: no new dependencies. Uses
  `System.Directory.getXdgDirectory` (already transitively available via
  `directory ^>=1.3`, currently in both packages' `build-depends`).
- **Option 2 (embed full)**: adds `containers ^>=0.7` to
  `nihongo-cli/nihongo-cli.cabal` (currently only declared in
  `nihongo-core`). `file-embed ^>=0.0.16` is already declared. No new
  external system dependencies.
- **Option 3 (embed subset)**: same as option 2.

System tools required (provided by `flake.nix`'s devShell): `rsvg-convert`
from `librsvg`. Already required by EP-4; this plan adds no new system
requirement under any option.

Modules added during spike milestones (intentionally on throwaway
branches, not on `master`):

    nihongo-cli/src/Nihongo/Kanji/KanjiVg/Embedded.hs   (B and C)
    nihongo-cli/data/joyou-codepoints.txt               (C only)

Modules potentially added by Milestone E:

- Option 1: none.
- Option 2 or 3: `Nihongo.Kanji.KanjiVg.Embedded`, exposed from
  `nihongo-cli` (path `nihongo-cli/src/Nihongo/Kanji/KanjiVg/Embedded.hs`).

Module signatures introduced under options 2 and 3:

    module Nihongo.Kanji.KanjiVg.Embedded where

      embeddedSvgBytes :: Nihongo.Kanji.Kanji -> Maybe Data.ByteString.ByteString
      embeddedCount    :: Int

`embeddedSvgBytes` returns `Nothing` for codepoints outside the embedded
set (always for option 2 only when the codepoint is also outside KanjiVG,
since KanjiVG's plain set is a strict superset of the codepoints any
caller could ever ask for).

Modules potentially modified by Milestone E:

- Option 1: `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`
  (`resolveKanjiVgRoot` adds an XDG-data-home candidate;
  `defaultKanjiVgRoot` rewrites the error string).
- Option 2 or 3: `nihongo-cli/src/Nihongo/Kanji/Png.hs`
  (`kanjiPngPath` falls back to the embedded bytes when `findStrokeSvg`
  returns `Nothing`); `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`
  (`runShow` does the same before invoking `parseStrokeOrderFile` and
  `displaySvg`); `nihongo-cli/nihongo-cli.cabal`
  (`exposed-modules`, `build-depends`, `extra-source-files`).

Help-topic files potentially modified by Milestone E:

    nihongo-cli/help/kanji-png.md
    nihongo-cli/help/kanji-show.md

Public APIs that downstream plans may rely on after Milestone E:

- Option 1: no API change. The `Nihongo.Kanji.KanjiVg` module's exported
  surface is unchanged; only its internal candidate list and error string
  shift.
- Option 2 or 3: `Nihongo.Kanji.KanjiVg.Embedded.embeddedSvgBytes` becomes
  the canonical "give me the bytes for this kanji from the binary"
  function. Future callers should prefer it over composing
  `findStrokeSvg` with `BS.readFile` themselves when they only need the
  bytes (no on-disk path).

Files added by this plan (to `master`, not counting spike branches):

- Option 1: none.
- Option 2 or 3: `nihongo-cli/src/Nihongo/Kanji/KanjiVg/Embedded.hs`,
  and (option 3 only) `nihongo-cli/data/joyou-codepoints.txt`.

Files modified by this plan (to `master`):

- Always: `docs/plans/8-evaluate-file-embedding-the-kanjivg-svg-corpus-into-the-nihongo-binary.md`
  (this file).
- Option 1: `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`,
  `nihongo-cli/help/kanji-png.md`, `nihongo-cli/help/kanji-show.md`,
  `nihongo-cli/src/Nihongo/Cli/Help.hs` (touch only — to force rebuild
  of the help-topic embeds, per the cabal/file-embed gotcha already
  documented at the top of that module).
- Option 2 or 3: `nihongo-cli/nihongo-cli.cabal`,
  `nihongo-cli/src/Nihongo/Kanji/Png.hs`,
  `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`,
  `nihongo-cli/help/kanji-png.md`, `nihongo-cli/help/kanji-show.md`,
  `nihongo-cli/src/Nihongo/Cli/Help.hs` (touch).

Files deleted by this plan: none on `master`. The spike branches
(`spike/ep8-embed-full`, `spike/ep8-embed-joyou`) are themselves deleted
in Milestone F.
