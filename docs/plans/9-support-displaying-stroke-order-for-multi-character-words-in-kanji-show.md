---
id: 9
slug: support-displaying-stroke-order-for-multi-character-words-in-kanji-show
title: "Support displaying stroke order for multi-character words in kanji show"
kind: exec-plan
created_at: 2026-05-06T15:11:14Z
intention: "intention_01kqyxd4ppe2et00333evvmweq"
---

# Support displaying stroke order for multi-character words in kanji show

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today, `nihongo kanji show` accepts exactly one Japanese character. Passing a
word like `食べる` or `日本語` aborts with `expected a single character (got
more)` (see `Nihongo.Cli.Commands.Kanji.Show.readSingleKanji` at
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs:133-143`). The same is
true when piping: `echo 漢字 | nihongo kanji show` errors out before any
useful output. Users who want to study a word currently have to invoke the
command once per character.

After this plan, the same command accepts a multi-character word and prints
one stroke-order section per character, in input order, separated by a
blank line. The single-character case continues to work byte-identically
to today (no regression). The user-visible win is direct:

    nihongo kanji show 漢字

prints first the existing `漢 (U+6F22, 13 strokes)` block and image, then
a blank line, then `字 (U+5B57, 6 strokes)` and its block and image. Same
for `echo 食べる | nihongo kanji show` (yielding three sections: 食, べ,
る). All existing flags (`--format`, `--no-images`, `--kanjivg-dir`) keep
their current semantics, applied uniformly to every character.

You will know it works when every invocation in *Validation and Acceptance*
below produces the documented output. The acceptance set covers: the
single-character case (unchanged), a two-kanji compound, a kanji+kana
mixed word, piped stdin, ASCII-only rejection, and partial-success
behaviour when KanjiVG has no entry for one character in the middle of
the word.

This plan is intentionally narrow. It does **not** change the `kanji
png` subcommand (`Nihongo.Cli.Commands.Kanji.Png.runPng`); that command
also has a `readSingleKanji` and could benefit from analogous treatment,
but its output contract — a single absolute path on stdout, suitable for
shell substitution — is different enough that extending it is a
follow-up plan, recorded as a Decision Log entry below. This plan also
does **not** introduce horizontal image composition, parallel
rasterisation, or any new caching: each character is processed
sequentially with the existing `displaySvg` pipeline. Both restrictions
are recorded as decisions.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone A — 2026-05-06: Added `parseKanjis :: Text -> Either KanjiParseError (NonEmpty Kanji)`, `KanjiParseError`, and `renderKanjiParseError` to `Nihongo.Kanji` (file: `nihongo-core/src/Nihongo/Kanji.hs`). Whitespace stripped via `Text.filter (not . isSpace)`; first non-Japanese character returns `KpeNotJapanese`; empty/all-whitespace returns `KpeEmpty`. Builds clean under `-Wall`; `cabal test nihongo-core` still passes (8/8).
- [ ] Milestone B: Wire `parseKanjis` into `Nihongo.Cli.Commands.Kanji.Show.runShow` (file: `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`). Replace the single-`Kanji` pipeline with a `traverse_`-style loop that prints one section per kanji separated by a blank line. The KanjiVG root and image-capability detection happen once outside the loop.
- [ ] Milestone C: Decide and implement per-character missing-SVG behaviour. Default: print the header line and a single `(no KanjiVG entry)` body line for that character, continue with the rest of the word, and exit non-zero only if **every** character lacked an entry. Record decision in the Decision Log.
- [ ] Milestone D: Update `nihongo-cli/help/kanji-show.md` to document the multi-character behaviour, the partial-success policy, and the unchanged single-character contract.
- [ ] Milestone E: Verify by running every invocation listed in *Validation and Acceptance* against `cabal run nihongo --` and pasting transcripts (header lines + first stroke line + section separators) into Outcomes & Retrospective.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Scope the change to `kanji show` only; leave `kanji png`
  unchanged in this plan.
  Rationale: `kanji png` exists to produce a single absolute path on
  stdout for shell substitution (see the module header comment in
  `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Png.hs:1-7` —
  *"Designed to be safe in shell substitution: stdout carries only
  the path on success"*). Extending it to print multiple paths
  (one per line, or NUL-separated) is a sensible follow-up but
  changes its contract in ways worth a separate plan and a
  separate user conversation. Record `kanji show` first; revisit
  `png` after this ships.
  Date: 2026-05-06.

- Decision: New helper lives in `Nihongo.Kanji` (the core library),
  not in a CLI-side module.
  Rationale: `mkKanji` is already the smart constructor exposed
  from there, and parsing a `Text` of multiple kanji is a
  domain-shaped operation, not a CLI concern. Keeping it in core
  also means a future `kanji png`, REPL, or library consumer can
  reuse it without introducing a CLI dependency.
  Date: 2026-05-06.

- Decision: Reject ASCII / non-Japanese input characters strictly,
  rather than silently skipping them.
  Rationale: A user who pastes `I want 食べる` is more likely to
  have made a copy-paste mistake than to want a partial result.
  Strict rejection produces a clear error
  (`not a Japanese character: I`) that points at the offending
  codepoint. Whitespace is the only exception: leading / trailing
  / interior whitespace is stripped before character validation,
  so `食 べ る` and `食べる` produce the same three-character
  result.
  Date: 2026-05-06.

- Decision: Partial-success semantics for missing KanjiVG entries.
  When KanjiVG has no `<5-hex>.svg` for a single character in a
  multi-character word, emit the header (e.g. `々 (U+3005, ?
  strokes)`) followed by a body line `(no KanjiVG entry)` and
  continue. Exit code is `0` if at least one character produced a
  full section, and non-zero (1) only if every character was
  missing.
  Rationale: KanjiVG covers most jōyō kanji and all
  hiragana/katakana, but rare characters and the iteration mark `々`
  may be absent. Aborting the whole word on one missing entry
  would be hostile to a user typing a real word; silently skipping
  it would lose information about which character was unrecognised.
  The "header + placeholder body" middle ground keeps the output
  shape uniform and tells the user which character was the problem.
  Date: 2026-05-06.

- Decision: Image rendering iterates sequentially, one inline image
  per character, separated by the existing `imageRows` newlines.
  Rationale: The Kitty graphics protocol (see
  `Nihongo.Terminal.Image.displayImage` at
  `nihongo-cli/src/Nihongo/Terminal/Image.hs:98-111`) emits an APC
  escape and then `replicateM_ imageRows (BS8.hPut IO.stdout
  "\n")` to advance the cursor. Stacking images is just calling
  `displaySvg` in a loop. Side-by-side composition would require
  custom column control sequences and is out of scope. Users with
  long words who find the vertical scrolling excessive can pass
  `--format text`.
  Date: 2026-05-06.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This repository is a Haskell project that builds the `nihongo` CLI, a
terminal-first Japanese learning companion. The project is split across
two cabal packages connected by `cabal.project`:

- `nihongo-core` (path: `nihongo-core/`) — domain types and pure logic.
  Exports the `Kanji` newtype and its smart constructor `mkKanji` from
  `nihongo-core/src/Nihongo/Kanji.hs`. Also hosts the project prelude
  `Nihongo.Prelude` (`nihongo-core/src/Nihongo/Prelude.hs`) which
  re-exports `Data.List.NonEmpty.NonEmpty`, `Data.Maybe.fromMaybe`, the
  `Text` type, and the lens vocabulary.
- `nihongo-cli` (path: `nihongo-cli/`) — `optparse-applicative` parsers,
  the `runCli` entry point, and IO orchestration. Exports the
  `nihongo` executable.

**Glossary of terms used below:**

- **KanjiVG** — an open-source SVG corpus that draws each Japanese
  character as an ordered list of `<path>` elements (one per stroke).
  This repository ships it as a git submodule at `data/kanjivg/`. Each
  character is a file `data/kanjivg/kanji/<5-hex>.svg`, where `<5-hex>`
  is the Unicode codepoint padded to five lowercase hex digits (e.g.
  `06f22.svg` for 漢, U+6F22). Coverage extends beyond the jōyō kanji
  to most CJK Unified Ideographs (Ext A included), full hiragana
  (U+3040–U+309F), and full katakana (U+30A0–U+30FF). Some
  characters — notably the iteration mark `々` (U+3005) — are not
  covered.

- **`Kanji` newtype** — `newtype Kanji = Kanji { unKanji :: Char }`,
  defined at `nihongo-core/src/Nihongo/Kanji.hs:18`. The smart
  constructor `mkKanji :: Char -> Either KanjiError Kanji` accepts only
  characters in the four Unicode blocks above; everything else
  (including ASCII and emoji) returns `Left (KanjiOutOfRange c)`. The
  helper `kanjiCodepointHex` (same file, line 45) renders a `Kanji` as
  the five-digit hex codepoint KanjiVG uses for its filenames.

- **Kitty graphics protocol** — an ANSI extension supported by Kitty,
  WezTerm, and Ghostty for inline-image rendering. The implementation
  in this project lives at
  `nihongo-cli/src/Nihongo/Terminal/Image.hs`; the high-level entry
  point is `displaySvg :: ImageCapability -> Text -> FilePath -> IO ()`
  (line 229). Each rendered image takes `imageRows = 20` rows of
  vertical space (line 73). When the terminal does not support the
  protocol, `displaySvg` prints a dim `[Image: <label>]` placeholder
  instead.

- **Stroke order** — the canonical drawing order of the strokes that
  make up a character. `parseStrokeOrderFile :: FilePath -> IO (Either
  ParseError StrokeOrderInfo)` lives in
  `nihongo-core/src/Nihongo/Kanji/StrokeOrder.hs`; it returns a list of
  `Stroke` values which `runShow` formats one per line.

**The current single-character pipeline (the thing we are
generalising), with line numbers from
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`:**

1. `Stdin.getTextInput inputArg` (line 114) — returns the positional
   argument if present, otherwise the trimmed contents of piped stdin,
   otherwise `Nothing`.
2. `readSingleKanji t` (line 117, defined at line 133) — strips
   whitespace, requires `Text.uncons` to yield a single `Char` with
   empty remainder, and runs `mkKanji` on that char. Multi-character
   input fails here.
3. `resolveKanjiVgRoot dirOverride` (line 118) — the `--kanjivg-dir`
   override → `NIHONGO_KANJIVG_DIR` env var → `<cwd>/data/kanjivg`
   priority chain.
4. `findStrokeSvg root kanji` (line 122) — turns a resolved root and a
   `Kanji` into a `Maybe FilePath`.
5. `parseStrokeOrderFile svg` (line 126) — parses the SVG into
   `StrokeOrderInfo`.
6. `detectImageCapabilityWithOverride noImages` (line 130) — runs once
   per invocation; observes `--no-images`, `KITTY_WINDOW_ID`, `TERM`,
   `TERM_PROGRAM`, `TMUX`. Returns `KittyGraphics` or `NoImageSupport`.
7. `printOutput fmt cap kanji info svg` (line 131, defined at line 145)
   — prints header, blank line, numbered strokes, blank line, then
   either an inline image or a `[Image: <label>]` placeholder
   depending on `cap` and `fmt`.

The change in this plan replaces step 2 with a list-producing parser
and wraps steps 4-7 in a loop. Steps 3 and 6 stay outside the loop —
the KanjiVG root is the same for every character in the word, and
image capability is a property of the terminal that does not change
mid-output.

**A relevant prior plan, checked into this repo:**
`docs/plans/5-implement-kanji-show-command.md` (EP-5) is the original
implementation of `kanji show`. Read it to understand how the pieces
were composed; this plan does not duplicate that material.


## Plan of Work

The work is a small surface change with a careful per-character output
contract. Five milestones, each independently verifiable.


### Milestone A — `parseKanjis` lives in `Nihongo.Kanji`

**Scope.** Add a single new function and a new error type to
`nihongo-core/src/Nihongo/Kanji.hs`. No call site changes; the
existing `mkKanji`, `unKanji`, `kanjiCodepointHex`, and `KanjiError`
remain untouched. The CLI keeps using `mkKanji` until Milestone B.

**What will exist at the end of this milestone.**

- A new exported error type `KanjiParseError` covering the two failure
  modes a multi-character parser can hit:

      data KanjiParseError
        = KpeEmpty                -- ^ No non-whitespace characters.
        | KpeNotJapanese !Char    -- ^ A non-Japanese character was found.
        deriving stock (Eq, Show)

- A new exported function:

      parseKanjis :: Text -> Either KanjiParseError (NonEmpty Kanji)

  Behaviour: filter out all Unicode whitespace from the input, then
  fold each remaining `Char` through `mkKanji`. On `Left
  (KanjiOutOfRange c)`, return `Left (KpeNotJapanese c)` for the
  *first* offending character (preserve the user's reading order). On
  empty input after the whitespace strip, return `Left KpeEmpty`.
  Otherwise return `Right (NE.fromList kanjis)`. `NonEmpty` from
  `Data.List.NonEmpty` is already in scope via `Nihongo.Prelude`.

- Update the module export list in
  `nihongo-core/src/Nihongo/Kanji.hs:4-11` to include the two new
  names.

- A renderer suitable for stderr:

      renderKanjiParseError :: KanjiParseError -> Text
      renderKanjiParseError KpeEmpty =
        "expected at least one Japanese character"
      renderKanjiParseError (KpeNotJapanese c) =
        "not a Japanese character: " <> Text.singleton c

  Exporting the renderer keeps the CLI from re-implementing the
  message and prevents drift if a future error constructor is added.

**Whitespace policy.** Use `Data.Char.isSpace` via
`Text.filter (not . isSpace)` to strip all whitespace. This catches
ASCII space, tab, newline, full-width space `　` (U+3000), and the
ideographic space variants — none of which we want to error on.

**Commands and acceptance.**

    cd /Users/shinzui/Keikaku/bokuno/nihongo
    cabal build nihongo-core

The package builds cleanly with `-Wall` (no new warnings — note that
`Nihongo.Kanji` already uses `-Wmissing-export-lists`). At this point
the helper exists but is unused; the CLI's `kanji show` and `kanji
png` commands still behave as they do on `master`. `cabal test
nihongo-core` continues to pass.


### Milestone B — `runShow` consumes `parseKanjis`

**Scope.** Replace `readSingleKanji` in
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs` with a multi-
character flow that uses `parseKanjis`. Reorder `runShow` so that
`resolveKanjiVgRoot` and `detectImageCapabilityWithOverride` are
called once *outside* the per-character loop; only the per-character
work (SVG lookup + parse + print) iterates.

**What will exist at the end of this milestone.**

The body of `runShow` becomes:

    runShow (ShowCommand inputArg fmt noImages dirOverride) = do
      mInput <- Stdin.getTextInput inputArg
      raw <- case mInput of
        Nothing -> die "expected a Japanese word as a positional argument or on stdin"
        Just t  -> pure t
      kanjis <- case parseKanjis raw of
        Left e  -> die (renderKanjiParseError e)
        Right ks -> pure ks
      mroot <- resolveKanjiVgRoot dirOverride
      root <- case mroot of
        Nothing -> die "could not find the KanjiVG corpus; see `nihongo help kanji-show`"
        Just r  -> pure r
      cap <- Image.detectImageCapabilityWithOverride noImages
      let total = NE.length kanjis
      results <- traverse (renderOne fmt cap root) (NE.zip (NE.fromList [1 .. total]) kanjis)
      let anyOk = any id results
      unless anyOk exitFailure

`renderOne` is a new helper, defined in the same module:

    renderOne
      :: OutputFormat
      -> Image.ImageCapability
      -> KanjiVgRoot
      -> (Int, Kanji)
      -> IO Bool
    renderOne fmt cap root (idx, kanji) = do
      when (idx > 1) (TIO.putStrLn "")  -- separator between sections
      mPath <- findStrokeSvg root kanji
      case mPath of
        Nothing -> do
          renderMissingHeader kanji  -- header + "(no KanjiVG entry)" line
          pure False
        Just svg -> do
          result <- parseStrokeOrderFile svg
          case result of
            Left err -> do
              TIO.hPutStrLn IO.stderr
                ("warning: failed to parse SVG for "
                 <> Text.singleton (unKanji kanji)
                 <> ": " <> Text.pack (show (err :: ParseError)))
              renderMissingHeader kanji
              pure False
            Right info -> do
              printOutput fmt cap kanji info svg
              pure True

`renderMissingHeader` prints `<glyph> (U+<hex>, ? strokes)` followed
by `(no KanjiVG entry)`. It deliberately uses `?` for the stroke
count so the header shape stays uniform with the success case.

The existing `header` and `printOutput` helpers stay as-is. Delete
`readSingleKanji` (no remaining callers).

**Imports.** Add `import Data.List.NonEmpty qualified as NE` and
`import Nihongo.Kanji (parseKanjis, renderKanjiParseError, ...)`. The
`NonEmpty` *type* is already in scope via the prelude; we only need
the qualified module for `length`, `zip`, and `fromList`.

**Commands and acceptance.**

    cd /Users/shinzui/Keikaku/bokuno/nihongo
    cabal build nihongo-cli
    cabal run nihongo -- kanji show 漢
    cabal run nihongo -- kanji show 漢字
    echo 食べる | cabal run nihongo -- kanji show

The first invocation matches today's output byte-for-byte. The
second prints two sections separated by a blank line. The third
prints three sections. None of these should print warnings on
stderr (assuming the KanjiVG submodule is initialised).


### Milestone C — Pin down the partial-success case

**Scope.** Choose a real example where KanjiVG lacks a glyph, and
verify the partial-success path documented in the Decision Log
behaves as designed. The iteration mark `々` (U+3005) is the
canonical example: it is a CJK symbol, accepted by `mkKanji` only if
its codepoint falls in our ranges.

**Pre-flight check (do this first).**

    cd /Users/shinzui/Keikaku/bokuno/nihongo
    ls data/kanjivg/kanji/03005.svg 2>/dev/null && echo "covered" || echo "missing"

If the result is `missing`, `々` is the placeholder example we want.
But there is a second issue: `mkKanji '々'` returns
`Left (KanjiOutOfRange '々')` today, because U+3005 is in the **CJK
Symbols and Punctuation** block (U+3000–U+303F), which is *not* one
of the four ranges accepted by `mkKanji` (see
`nihongo-core/src/Nihongo/Kanji.hs:35-41`). So `々` would be rejected
by `parseKanjis` before the missing-SVG branch ever runs.

To exercise the partial-success path, find a CJK character whose
codepoint *is* accepted by `mkKanji` but whose SVG file is absent.
Candidates: rare Ext A characters such as `㐂` (U+3402). Verify with:

    ls data/kanjivg/kanji/03402.svg 2>/dev/null && echo "covered" || echo "missing"

If `missing`, use `㐂` in the multi-character verification below. If
`covered`, scan the assigned-but-missing range:

    bun run --print "
      // Find one Ext-A codepoint accepted by mkKanji but absent from KanjiVG
    " || true

A simpler shell approach:

    for cp in 3402 3403 3404 3405; do
      f=$(printf "%05x" $cp)
      [ -f data/kanjivg/kanji/$f.svg ] || { printf 'U+%04X is missing\n' $cp; break; }
    done

Use the first hit as the placeholder example. Record the chosen
codepoint and the test transcript in *Surprises & Discoveries*.

**What will exist at the end of this milestone.** A recorded test
showing that `cabal run nihongo -- kanji show <hit><漢>` produces:

    <hit> (U+XXXX, ? strokes)
    (no KanjiVG entry)

    漢 (U+6F22, 13 strokes)

    1. ㇔ dot
    ...

…and exits `0` (because at least one section succeeded). And a
recorded test of `cabal run nihongo -- kanji show <hit>` (single
missing character) exits `1`.

**Acceptance.** Both transcripts pasted into Surprises & Discoveries
along with the chosen codepoint.


### Milestone D — Update help topic

**Scope.** Edit `nihongo-cli/help/kanji-show.md` to describe the new
behaviour. This file is rendered by `nihongo help kanji-show` (see
`Nihongo.Cli.Help`).

**What changes.** Replace the lead paragraph that says *"a single
Japanese character"* (line 2-3 of the help file) with prose that
covers both the single-character and the word case. Add a "Words"
subsection between "Use `--format ...`" and "## Requirements" that
documents:

- Whitespace inside input is stripped (`食 べ る` ≡ `食べる`).
- Non-Japanese characters cause a hard error (no silent skipping).
- KanjiVG misses are reported per-character but do not abort the
  rest of the word.
- Each character renders an independent inline image; long words
  scroll.
- Tip: `--format text` for terminal-friendly word study.

Also update the `argument` `help` string in the parser at
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs:71` from `"A
single Japanese character. Reads from stdin if omitted."` to
something like `"A Japanese character or word. Reads from stdin if
omitted."`. The `metavar` `KANJI` stays — changing it to `WORD`
would break compatibility with shell completions generated from the
old metavar.

**Acceptance.**

    cabal run nihongo -- help kanji-show
    cabal run nihongo -- kanji show --help

Both render the new wording. No other help topics or commands are
affected.


### Milestone E — Verification

**Scope.** Run every invocation in *Validation and Acceptance* below
and paste evidence into *Outcomes & Retrospective*.

**Acceptance.** Every case passes. Single-character output is
byte-identical to the pre-change output (capture both before and
after to compare). The `cabal test nihongo-core` and any nihongo-cli
test suite continue to pass with no new warnings under `-Wall`.


## Concrete Steps

All commands assume the working directory is the repository root,
`/Users/shinzui/Keikaku/bokuno/nihongo`, and that the Nix devshell is
active (`nix develop` or via `direnv allow`). The Nix devshell is what
provides `cabal`, `ghc`, and `rsvg-convert` on `PATH`. Confirm with:

    which cabal
    which rsvg-convert

Both should resolve to paths inside `/nix/store/`.

**Step 1 — Capture the pre-change baseline.** Run the existing
single-character invocation and save its output for byte-comparison
later:

    cabal run -v0 nihongo -- kanji show 漢 > /tmp/ep9-baseline-han.txt 2>&1
    cabal run -v0 nihongo -- kanji show 一 > /tmp/ep9-baseline-ichi.txt 2>&1

`-v0` silences cabal's `Resolving dependencies...` chatter so the
captured output contains only the program's stdout/stderr. Keep these
files around through Milestone E.

**Step 2 — Implement Milestone A.**

Edit `nihongo-core/src/Nihongo/Kanji.hs`. The new export list looks
like:

    module Nihongo.Kanji
      ( Kanji,
        unKanji,
        mkKanji,
        kanjiCodepointHex,
        KanjiError (..),
        KanjiParseError (..),
        parseKanjis,
        renderKanjiParseError,
      )
    where

Add `import Data.Char (isSpace)` and `import Data.List.NonEmpty
qualified as NE` (the prelude already brings in the `NonEmpty` type
constructor unqualified).

Build:

    cabal build nihongo-core

Expected: clean build, no `-Wall` warnings, no `-Wmissing-export-lists`
warning (which would fire if the new symbols were not added to the
export list).

**Step 3 — Implement Milestone B.**

Edit `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs` per the
*Plan of Work* section above. After the edit, build and smoke-test:

    cabal build nihongo-cli
    cabal run -v0 nihongo -- kanji show 漢 > /tmp/ep9-after-han.txt 2>&1
    diff /tmp/ep9-baseline-han.txt /tmp/ep9-after-han.txt

The diff must be empty: the single-character path is byte-stable. If
it is not empty, investigate before proceeding (most likely cause: an
extra leading or trailing blank line introduced by the loop's
separator logic).

Now exercise the new path:

    cabal run -v0 nihongo -- kanji show 漢字

Expected (the trailing inline image is replaced here by `[Image: ...]`
for readability — actual output prints either the Kitty escape or the
placeholder depending on the terminal):

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

    [Image: 漢]

    字 (U+5B57, 6 strokes)

    1. ㇔ dot
    2. ㇔ dot
    3. ㇕ turn-down
    4. ㇐ horizontal
    ... (etc, 6 strokes total) ...

    [Image: 字]

The exact stroke count for 字 (6) and 漢 (13) is dictated by KanjiVG;
do not hand-curate.

Pipe-mode test:

    echo 食べる | cabal run -v0 nihongo -- kanji show

Expected: three sections (食, べ, る) separated by blank lines.

Negative tests (Milestone B path):

    cabal run -v0 nihongo -- kanji show "I食べる"
    # → stderr: "not a Japanese character: I", exit 1

    cabal run -v0 nihongo -- kanji show ""
    # → stderr: "expected at least one Japanese character", exit 1

    echo "  " | cabal run -v0 nihongo -- kanji show
    # → stderr: "expected a Japanese word as a positional argument or on stdin"
    #   (Stdin.getTextInput trims whitespace and returns Nothing for empty.)

**Step 4 — Identify the placeholder codepoint (Milestone C).**

    for cp in $(seq 13313 13380); do
      f=$(printf "%05x" $cp)
      [ -f data/kanjivg/kanji/$f.svg ] || { printf 'U+%04X is missing (%s)\n' $cp $f; break; }
    done

Note the resulting codepoint and its glyph. (At time of writing: U+3402
㐂 is a likely candidate; verify in the running corpus.) Then:

    cabal run -v0 nihongo -- kanji show "㐂漢"
    echo $?

Expected: a `(no KanjiVG entry)` section for `㐂`, a full section for
`漢`, exit code `0`. And:

    cabal run -v0 nihongo -- kanji show "㐂"
    echo $?

Expected: a single `(no KanjiVG entry)` section, exit code `1`.

Paste both transcripts into *Surprises & Discoveries* with the chosen
codepoint named.

**Step 5 — Update help (Milestone D).**

Edit `nihongo-cli/help/kanji-show.md` and the parser metavar/help in
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs:69-71`. Verify:

    cabal run -v0 nihongo -- help kanji-show | head -20
    cabal run -v0 nihongo -- kanji show --help

Both should mention "word" or "characters" rather than implying
single-character-only.

**Step 6 — Final verification (Milestone E).** Run the full
*Validation and Acceptance* matrix.

**Step 7 — Commit.** Use one or two commits — one for the core helper
(Milestone A), one for the CLI wiring + help (Milestones B-D) — each
with a Conventional Commits header and an `ExecPlan:` and `Intention:`
git trailer:

    feat(cli): kanji show accepts multi-character words

    Replace single-character readSingleKanji with parseKanjis from
    nihongo-core. Iterate per character with a blank line separator,
    sharing one KanjiVG root resolution and one image-capability
    detection across the whole word. Report missing KanjiVG entries
    per character; exit non-zero only if every character was missing.

    ExecPlan: docs/plans/9-support-displaying-stroke-order-for-multi-character-words-in-kanji-show.md
    Intention: intention_01kqyxd4ppe2et00333evvmweq


## Validation and Acceptance

Each numbered case below is independently verifiable. Working directory:
`/Users/shinzui/Keikaku/bokuno/nihongo`. Where the inline image render
matters, the expected output is described in words; where only the
text matters, an exact transcript is given.

1. **Single-kanji compatibility (the no-regression check).**

       diff /tmp/ep9-baseline-han.txt <(cabal run -v0 nihongo -- kanji show 漢 2>&1)

   Expected: empty diff. The byte-for-byte equivalence is the
   strongest acceptance signal that the loop's separator logic, the
   `traverse` ordering, and the partial-success bookkeeping have not
   altered the single-kanji path.

       diff /tmp/ep9-baseline-ichi.txt <(cabal run -v0 nihongo -- kanji show 一 2>&1)

   Expected: empty diff (one-stroke kanji edge case still byte-stable).

2. **Two-kanji compound (positional).**

       cabal run -v0 nihongo -- kanji show 漢字

   Expected on stdout, in order: header `漢 (U+6F22, 13 strokes)`,
   blank line, 13 numbered stroke lines, blank line, image-or-
   placeholder for 漢, blank line (the section separator), header
   `字 (U+5B57, 6 strokes)`, blank line, 6 numbered stroke lines,
   blank line, image-or-placeholder for 字. Exit code `0`.

3. **Mixed kanji + hiragana (piped).**

       echo 食べる | cabal run -v0 nihongo -- kanji show

   Expected: three sections in order — 食, べ, る — separated by
   blank lines. Exit code `0`.

4. **Whitespace stripping.**

       cabal run -v0 nihongo -- kanji show "食 べ る"
       cabal run -v0 nihongo -- kanji show "食べる"

   Expected: byte-identical output. Use `diff` to confirm.

5. **Strict ASCII rejection.**

       cabal run -v0 nihongo -- kanji show "I食べる"; echo "exit=$?"

   Expected on stderr: `not a Japanese character: I`. Exit code `1`.
   No partial output on stdout.

6. **Empty input rejection.**

       cabal run -v0 nihongo -- kanji show ""; echo "exit=$?"

   Expected on stderr: `expected at least one Japanese character`.
   Exit code `1`.

       echo "" | cabal run -v0 nihongo -- kanji show; echo "exit=$?"

   Expected on stderr: `expected a Japanese word as a positional
   argument or on stdin` (because `Stdin.getTextInput` returns
   `Nothing` for empty piped input). Exit code `1`.

7. **Partial KanjiVG miss.** Using the codepoint identified in
   *Concrete Steps* Step 4 (call it `<X>`):

       cabal run -v0 nihongo -- kanji show "<X>漢"; echo "exit=$?"

   Expected: header for `<X>` followed by `(no KanjiVG entry)`,
   blank line, full 漢 section. Exit code `0`.

8. **Total KanjiVG miss.**

       cabal run -v0 nihongo -- kanji show "<X>"; echo "exit=$?"

   Expected: header for `<X>` followed by `(no KanjiVG entry)`. Exit
   code `1`.

9. **Format flags propagate to every character.**

       cabal run -v0 nihongo -- kanji show 漢字 --format text

   Expected: two text-only sections, no image lines, no `[Image: ...]`
   placeholders.

       cabal run -v0 nihongo -- kanji show 漢字 --format image --no-images

   Expected: two `[Image: 漢]` and `[Image: 字]` placeholder lines (no
   stroke text). The `--no-images` overrides the format choice's
   image rendering, falling back to placeholders (current behaviour
   of `displaySvg NoImageSupport`).

10. **`--kanjivg-dir` override applies to every character.** With a
    sibling KanjiVG checkout at `/tmp/kanjivg-alt`, run:

        cabal run -v0 nihongo -- kanji show 漢字 --kanjivg-dir /tmp/kanjivg-alt

    Expected: same output as case 2, but the SVGs were read from the
    override path. (Verify by `strace`-equivalent or by temporarily
    moving `data/kanjivg/kanji/06f22.svg` aside and confirming the
    command still succeeds.)

11. **Help text.**

        cabal run -v0 nihongo -- help kanji-show | grep -i word
        cabal run -v0 nihongo -- kanji show --help | grep -i word

    Expected: at least one matching line in each, mentioning that the
    command accepts a word.

12. **Test suite.**

        cabal test nihongo-core
        cabal test nihongo-cli  # if a test stanza exists; check first with: grep test-suite nihongo-cli/nihongo-cli.cabal

    Expected: all suites pass. The `nihongo-cli` cabal file as of
    this writing has no `test-suite` stanza; do not invent one for
    this plan.

Acceptance for the plan as a whole: every case 1-12 produces the
documented behaviour, and the transcripts of cases 2, 3, 7, and 8
are pasted verbatim into *Outcomes & Retrospective*.


## Idempotence and Recovery

Every step in this plan is safe to repeat.

- The cabal builds (`cabal build nihongo-core`, `cabal build
  nihongo-cli`) are pure functions of source state; running them
  twice produces the same artefacts. `dist-newstyle/` is the only
  side effect, and is git-ignored.

- The smoke-test invocations (`cabal run nihongo -- kanji show ...`)
  read only from the KanjiVG submodule and from the PNG cache at
  `<XDG_CACHE_HOME>/nihongo/strokes/` (or `~/.cache/nihongo/strokes/`).
  They never write into the repository tree. Re-running them populates
  cache entries and is otherwise idempotent.

- The PNG cache key includes a `cacheVersion` constant (currently
  `"v2:width=384"` at
  `nihongo-cli/src/Nihongo/Terminal/Image.hs:174`). If a future
  rasterisation parameter changes, bumping the constant naturally
  invalidates stale entries. This plan does not change rasterisation,
  so the constant stays as-is.

- The `/tmp/ep9-baseline-*.txt` files are the only state outside the
  repo this plan creates. They are safe to regenerate by re-running
  Step 1 of *Concrete Steps* before any Milestone-A code change.

**Rollback.** This plan is a small, self-contained set of edits to
two files (`nihongo-core/src/Nihongo/Kanji.hs` and
`nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`) plus one help
file (`nihongo-cli/help/kanji-show.md`). To undo: revert the commits
listed in *Concrete Steps* Step 7 (`git revert <SHA>`). No data
migrations, no schema changes, no flag-day deployments. The PNG
cache entries created during smoke testing remain valid under the
reverted code (they are content-addressed by SVG hash, not command
version).

**If a Milestone B build fails partway.** The most likely failure is
an import or export-list mismatch. The cabal error message names the
exact missing symbol; add it to the export list in
`Nihongo.Kanji` (or to the import list in `Show.hs`) and rebuild.
Because Milestone A (the helper) is already in the working tree at
that point, you do not need to revert anything — just fix the wiring.

**If the smoke tests in Step 3 produce a non-empty diff against the
baseline.** Inspect the diff. If it shows a leading or trailing blank
line difference, the loop separator (`when (idx > 1) (TIO.putStrLn
"")`) is firing on the first iteration or the last `printOutput`
ended with an extra newline. Adjust the separator until the
single-character case is byte-stable; re-run the diff.


## Interfaces and Dependencies

**No new package dependencies.** Every library this plan touches is
already in `nihongo-core/nihongo-core.cabal` or
`nihongo-cli/nihongo-cli.cabal`:

- `base` — for `Data.Char.isSpace` and `Data.List.NonEmpty` (the
  prelude already re-exports the `NonEmpty` constructor; this plan
  imports `Data.List.NonEmpty qualified as NE` for the `length`,
  `zip`, and `fromList` helpers).
- `text` — for `Text.filter`, `Text.singleton`, and so on. Already
  used throughout the project.
- `optparse-applicative` — already used for the existing parser; no
  changes to dependency surface, just a wording change to the
  `argument` `help` string.

**Module-level signatures that must exist at the end of each
milestone:**

End of Milestone A — `nihongo-core/src/Nihongo/Kanji.hs` exports:

    data KanjiParseError
      = KpeEmpty
      | KpeNotJapanese !Char
      deriving stock (Eq, Show)

    parseKanjis :: Text -> Either KanjiParseError (NonEmpty Kanji)
    renderKanjiParseError :: KanjiParseError -> Text

End of Milestone B — `nihongo-cli/src/Nihongo/Cli/Commands/Kanji/Show.hs`:

    runShow :: ShowCommand -> IO ()  -- unchanged signature
    -- internal helper, not exported:
    -- renderOne :: OutputFormat -> Image.ImageCapability -> KanjiVgRoot
    --           -> (Int, Kanji) -> IO Bool

The `ShowCommand` record, `showParser`, and `OutputFormat` are
unchanged in name and shape. The `readSingleKanji` private helper is
removed.

End of Milestone D — `nihongo-cli/help/kanji-show.md` documents the
multi-character behaviour; the parser's `argument` `help` text reads
"A Japanese character or word. Reads from stdin if omitted."

**Cross-module ordering inside `runShow`:**

1. Parse args (already done by optparse-applicative before `runShow`
   is called).
2. Read input via `Stdin.getTextInput`.
3. `parseKanjis` the input → `NonEmpty Kanji`.
4. `resolveKanjiVgRoot` (one IO call, shared across all kanji).
5. `detectImageCapabilityWithOverride` (one IO call, shared).
6. For each kanji: `findStrokeSvg` → `parseStrokeOrderFile` →
   `printOutput`. Print a blank-line separator before every section
   except the first.
7. Exit non-zero iff every section was a KanjiVG miss.

This sequencing preserves the per-invocation costs of the existing
single-kanji path (one root resolution, one capability detection)
and amortises the per-character costs across the loop.

**External services.** None new. `rsvg-convert` from `librsvg` is
invoked by `ensurePng` exactly as today; the only difference is it
gets called once per character instead of once per invocation.
