---
id: 1
slug: bootstrap-nihongo-cli-with-kanji-stroke-order
title: "Bootstrap nihongo CLI with kanji stroke order"
kind: master-plan
created_at: 2026-05-06T02:27:09Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
---

# Bootstrap nihongo CLI with kanji stroke order

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

`nihongo` is a terminal-first Japanese learning companion shipped as a Haskell CLI. By the
end of this initiative a user can run

    nihongo kanji show 漢

inside a Kitty-graphics-capable terminal (Kitty, WezTerm, Ghostty, or those wrapped in
`tmux` with passthrough enabled) and see two things on stdout: a numbered, human-readable
breakdown of the stroke order for the kanji 漢 (with each stroke labelled by its
direction, e.g. "1: ㇒ left-falling"), and an inline image of the kanji rendered from the
KanjiVG SVG, displayed via the Kitty graphics protocol. When the terminal does not
support Kitty graphics, the image is replaced with a dim `[Image: 漢]` placeholder; when
the user passes `--no-images`, only the text breakdown is shown. The kanji can also be
piped: `echo 漢 | nihongo kanji show`.

The scaffolding put in place to deliver that one feature is what makes the project a
viable foundation for future commands. After this initiative the project carries:

- Two cabal packages (`nihongo-core` library, `nihongo-cli` library + `nihongo`
  executable) on GHC 9.12 with `GHC2024` and the project-wide extension and warning
  baseline established by `haskell-jitsurei`.
- A meaningful `Nihongo.Prelude` re-exporting `Generic`, `Text`, `MonadIO`/`liftIO`,
  `NonEmpty`, `UTCTime`, lens, generic-lens labels, and aeson basics so that all
  modules can `import Nihongo.Prelude` and get the standard toolkit.
- The CLI bootstrap idioms from `haskell-jitsurei`: `--version` with embedded git SHA,
  a `help` subcommand backed by `file-embed`-compiled markdown topics with terminal-aware
  width handling that uses `terminal-size` (not `ansi-terminal`'s escape-sequence
  hack), a `completions {bash,zsh,fish}` subcommand, stdin auto-detection, and option
  groups for `--help` clarity.
- A `Nihongo.Pretty` module with the same ANSI helpers (`dim`, `bold`, `colored`) used by
  the same author's `kizamu` project, so future commands look consistent.
- The KanjiVG SVG corpus (about 12,000 glyphs, ~78 MB) attached as a git submodule at
  `data/kanjivg/` pinned to release tag `r20250816`, with a tiny lookup module that
  maps a `Char` to its `kanji/<5-digit lowercase hex>.svg` path.
- A `Nihongo.Kanji.StrokeOrder` parser that reads a KanjiVG SVG using `xml-conduit`,
  extracts the strokes from the `kvg:StrokePaths_*` group, sorts them by their
  `id="kvg:<cp>-s<N>"` index, and decorates each one with a human description by
  mapping its `kvg:type` (a CJK Stroke character such as `㇒`) through a constant
  table. The same module reads the radical/component decomposition from the nested
  groups (`kvg:element`, `kvg:position`, `kvg:radical`).
- A `Nihongo.Terminal.Image` module that ports `kizamu`'s capability detection (Kitty,
  WezTerm, Ghostty, plus tmux DCS passthrough) and Kitty graphics emitter, extended
  with an SVG-to-PNG rasterization step that shells out to the system tool
  `rsvg-convert` (declared in `flake.nix`) and caches results by content hash under
  `~/.cache/nihongo/strokes/<sha256>.png` so re-displaying a kanji never re-rasterizes.

Out of scope for this initiative: looking up kanji by reading or meaning, English glosses,
JLPT level filters, JMdict integration, animated stroke playback, Sixel or iTerm2 inline
image protocols, agent-assist commands, hierarchical config files, and command aliases.
Each of those is a candidate for its own future MasterPlan once the foundation is in
place.


## Decomposition Strategy

The initiative was decomposed by functional concern, following the MasterPlan
specification's principle of "fewer well-scoped plans over many granular ones." Five
work streams emerged naturally:

EP-1 (Foundations) owns everything that is not specific to kanji or stroke order: the
prelude, the shared cabal `common-options` stanza, the CLI bootstrap idioms (version,
help, completions, stdin, option groups, ANSI helpers), and the `flake.nix` runtime
inputs. It must come first because every other plan imports from `Nihongo.Prelude`,
extends the shared cabal stanza, or relies on the `flake.nix` having `rsvg-convert`
available.

EP-2 (KanjiVG submodule and lookup) owns the data source. It adds the git submodule,
defines the project's `Kanji` newtype, and provides `findStrokeSvg :: KanjiVgRoot -> Kanji
-> IO (Maybe FilePath)`. Splitting it from EP-3 keeps the submodule wiring (a one-time
filesystem and gitmodules concern) separate from the XML parsing work, and gives EP-3 a
clean dependency: a `FilePath` to read.

EP-3 (Stroke order parsing) owns reading the SVG and producing a structured value (list
of strokes plus component tree). It is pure, sits in `nihongo-core`, and can be
test-driven with a handful of bundled fixture SVGs without needing the full submodule
or any terminal capability.

EP-4 (Terminal image rendering) owns getting a PNG onto the terminal. It is independent
of stroke parsing because rendering takes any PNG file path; isolating it means future
commands (radicals, vocab cards) can reuse the module unchanged. It also owns the
SVG-to-PNG rasterization step, since rasterization is the precondition for Kitty's
`f=100,t=f` payload.

EP-5 (`kanji show` command) wires EP-2, EP-3, and EP-4 together behind a user-facing
optparse-applicative subcommand and adds the help topic that explains the feature.

Alternatives considered:

- *Merging EP-2 and EP-3 into a single "KanjiVG" plan.* Rejected because the work is
  qualitatively different (filesystem + submodule wiring versus XML parsing + stroke
  type taxonomy) and they differ in scope by roughly a factor of three; a merged plan
  would unbalance the slate.
- *Merging EP-4 into EP-5.* Rejected because the image module is reusable infrastructure
  that the rest of the project will lean on; making it a standalone plan signals that
  it has its own tests, its own fallback behavior, and its own opt-out flag, and that
  changing it must consider all callers, not just `kanji show`.
- *Dropping EP-1's CLI infrastructure (version/help/completions/stdin) and adding it
  later.* Rejected because the current `Nihongo.Cli.runCli` is a stub and `kanji show`
  would otherwise inherit a deficient parser shape (the help-width parser-shape trap
  documented in `haskell-jitsurei/cli/help-width.md` requires a particular structure
  from day one). Establishing the pattern now prevents later rework.

Five plans is at the upper bound of the "two to seven" guidance; phases were not
introduced because the dependency graph is shallow (EP-1 is the only universal
dependency; EP-2/3/4 fan out from it and merge again at EP-5).


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Establish nihongo CLI foundations | docs/plans/1-establish-nihongo-cli-foundations.md | None | None | Complete |
| 2 | Add KanjiVG submodule and lookup | docs/plans/2-add-kanjivg-submodule-and-lookup.md | EP-1 | None | Complete |
| 3 | Parse KanjiVG stroke order metadata | docs/plans/3-parse-kanjivg-stroke-order-metadata.md | EP-1 | EP-2 | Complete |
| 4 | Render images in the terminal via Kitty graphics | docs/plans/4-render-images-in-the-terminal-via-kitty-graphics.md | EP-1 | None | Complete |
| 5 | Implement kanji show command | docs/plans/5-implement-kanji-show-command.md | EP-1, EP-2, EP-3, EP-4 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-1 has no dependencies; everything else depends on it because they all `import
Nihongo.Prelude`, extend the shared cabal `common-options` stanza, or assume that
`flake.nix` provides `rsvg-convert` and a recent `git` for submodule operations.

EP-2 hard-depends on EP-1 only. It introduces the `Kanji` newtype and the
`Nihongo.Kanji.KanjiVg` module; once those exist anyone else can consume them.

EP-3 hard-depends on EP-1 and soft-depends on EP-2. The soft dependency reflects the
fact that EP-3's tests use bundled fixture SVGs (so EP-3 can be implemented and merged
before EP-2 lands), but in production its callers want the `Kanji` newtype from EP-2 to
reach a `FilePath`. If EP-2 is not yet complete when EP-3 starts, EP-3 may temporarily
work against `FilePath` directly and adjust the public signature once EP-2 lands.

EP-4 hard-depends on EP-1 only. It is independent of EP-2 and EP-3: `displayImage`
takes any PNG file path. EP-4 can therefore proceed in parallel with EP-2 and EP-3 once
EP-1 is complete.

EP-5 hard-depends on EP-1, EP-2, EP-3, and EP-4. It is the integration plan and cannot
start until all four upstream plans are at least functionally complete (they need not be
fully polished, but their public APIs must be stable).

The shortest critical path is EP-1 → EP-2 → EP-5 (or EP-1 → EP-3 → EP-5, or EP-1 → EP-4
→ EP-5); EP-2, EP-3, and EP-4 can run concurrently after EP-1 finishes, which is the
intended parallelism.


## Integration Points

`Nihongo.Prelude` (module). Defined by EP-1 in `nihongo-core/src/Nihongo/Prelude.hs`;
imported by every module produced by EP-2, EP-3, EP-4, EP-5. Per `haskell-jitsurei`'s
custom-prelude pattern, it re-exports lens, generic-lens labels, `Text`, `Generic`,
`MonadIO`/`liftIO`, `NonEmpty`, `UTCTime`, and aeson basics. Later plans must not add
their own ad-hoc preludes; if a re-export is missing, extend `Nihongo.Prelude` itself.

Shared cabal `common common-options` stanza. Defined by EP-1 in both
`nihongo-core/nihongo-core.cabal` and `nihongo-cli/nihongo-cli.cabal`. EP-1 sets the
final extension list (adds `MultilineStrings`) and warning options. Later plans extend
cabal *only* by adding new modules and dependencies to the `library`/`executable`
stanzas; they must not edit the shared `common-options` block unless they need a
project-wide extension change, in which case they must update both cabal files in
lockstep and record the change in this MasterPlan's Decision Log.

`Kanji` newtype and the `Nihongo.Kanji.*` module namespace. Defined by EP-2 in
`nihongo-core/src/Nihongo/Kanji.hs` (the type) and `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`
(the lookup). `Kanji` is `newtype Kanji = Kanji { unKanji :: Char }` with a smart
constructor that rejects non-Japanese codepoints. EP-3 places its parser at
`nihongo-core/src/Nihongo/Kanji/StrokeOrder.hs` and consumes `Kanji` only in helper
constructors; the parser itself works on `FilePath`. EP-5 consumes both modules.

`flake.nix` runtime inputs. EP-1 owns the file. By the end of EP-1 the dev shell
provides `pkgs.librsvg` (which gives `rsvg-convert`) and `pkgs.gitMinimal`. EP-4
verifies `rsvg-convert` at start-up time (graceful error if missing) but does not edit
`flake.nix` itself.

`~/.cache/nihongo/` cache root. EP-4 owns it under the path
`~/.cache/nihongo/strokes/<sha256>.png`. EP-5 calls into EP-4's API and never touches
the cache directly. The `XDG_CACHE_HOME` env var is honoured; otherwise `~/.cache` is
the default.

`--kanjivg-dir` flag. Declared by EP-2 (along with the `KanjiVgRoot` resolution
logic that consults the flag, then the `NIHONGO_KANJIVG_DIR` env var, then the
submodule path relative to the executable working tree, in that order). EP-5 wires the
flag into the `kanji show` subparser via `parserOptionGroup "Source"`.

`--no-images` flag. Declared by EP-4 (along with the `ImageCapability` ADT that
short-circuits to `NoImageSupport` when the flag is set). EP-5 wires the flag into the
`kanji show` subparser via `parserOptionGroup "Image"`.

CLI top-level subcommand registry. EP-1 establishes the pattern in
`nihongo-cli/src/Nihongo/Cli.hs`: a `Command` ADT and an `hsubparser` block that uses
`commandGroup` to organize subcommands. EP-1 adds `version`, `help`, and `completions`;
EP-5 adds the `kanji` subcommand group. Both plans modify the same file; EP-5 must
follow the pattern EP-1 establishes (a `Nihongo.Cli.Commands.<Group>` module with a
`parser :: Parser <GroupCommand>` and `runCommand :: <GroupCommand> -> IO ()` exported,
wired into `Nihongo.Cli`).


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan
and the milestone. This section provides an at-a-glance view of the entire initiative.

- [x] EP-1: Expand `Nihongo.Prelude` per haskell-jitsurei custom-prelude pattern. (2026-05-05)
- [x] EP-1: Add `Nihongo.Pretty` ANSI helpers in `nihongo-cli`. (2026-05-05)
- [x] EP-1: Add `Nihongo.Cli.Stdin`, `Nihongo.Cli.Width`, and `Nihongo.Cli.Version` modules. (2026-05-05)
- [x] EP-1: Add `help`, `completions`, and `--version` subcommands; replace stub parser with the parser-shape-safe pattern. (2026-05-05)
- [x] EP-1: Update `flake.nix` (`librsvg`, `gitMinimal`) and `cabal` `common-options` (`MultilineStrings`, full warning set). (2026-05-05; MultilineStrings added; warning set unchanged from scaffold which already matched the plan's baseline)
- [x] EP-2: Add `data/kanjivg/` git submodule pinned to `r20250816`. (2026-05-05; tag resolves to commit `bd13ffbcc`, not the `544d319f` master HEAD originally referenced)
- [x] EP-2: Implement `Nihongo.Kanji` (newtype + smart constructor) and `Nihongo.Kanji.KanjiVg` (root resolution + `findStrokeSvg`). (2026-05-05; also added a temporary hidden `kanji-debug-path` subcommand for end-to-end validation — EP-5 removes it)
- [x] EP-3: Implement `Nihongo.Kanji.StrokeOrder` SVG parser with `xml-conduit`. (2026-05-05; corrected the kvg-namespace match shape — see Surprises below)
- [x] EP-3: Build the CJK Stroke type → English description table. (2026-05-05)
- [x] EP-3: Add fixture-based tests covering 漢, あ, and one variant-only edge. (2026-05-05; 8 examples, 0 failures via `cabal test all`)
- [x] EP-4: Implement `Nihongo.Terminal.Image` (capability detection, Kitty emitter, tmux passthrough, fallback). (2026-05-05; tmux-probe path returns `KittyGraphics` for outer `WezTerm`/`ghostty`/`kitty`; emitter wraps `\\e_Ga=T,f=100,t=f,r=12;<base64-path>` in tmux DCS passthrough when `TMUX` is set.)
- [x] EP-4: Implement SVG → PNG rasterization via `rsvg-convert` with content-hash caching under `~/.cache/nihongo/strokes/`. (2026-05-05; first call rasterises 109×109 RGBA PNG, second call hits cache.)
- [ ] EP-5: Add `kanji show` subcommand with stdin fallback, output/image/source option groups.
- [ ] EP-5: Add `help/kanji-show.md` topic via `file-embed` and register it in the help registry.
- [ ] EP-5: End-to-end manual verification with 漢 in a Kitty-capable terminal and inside `tmux`.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- **OverloadedRecordDot is not in GHC2024.** The original EP-1 code samples
  used `opts.command` syntax, which requires `OverloadedRecordDot` (separate
  from `OverloadedLabels`). Per the haskell-jitsurei
  `core/record-patterns.md` reference, the project's record convention uses
  generic-lens labels (`record ^. #field`), not the dot shorthand. EP-2
  through EP-5 must follow the same convention: every record-bearing data
  type derives `Generic` with strict (`!`) fields, and field access uses
  `^. #field` (or pattern matching with field puns for destructuring).

- **aarch64-darwin link failure for the `Paths_*` autogen module.** Linking
  the executable failed with `ld: Absolute addressing not allowed in arm64
  code` on relocations between `Nihongo.Cli.Version.appVersion` and
  `Paths_nihongo_cli.version`. Fix: declare `Paths_<package>` under both
  `autogen-modules:` and `other-modules:` in the library stanza, mirroring
  kizamu's cabal layout. Any later plan that adds another package or
  introduces a module using `Paths_*` must do the same.

- **`Options` wrapper deleted; CLI parser yields `Command` directly.** The
  EP-1-as-authored plan included a `newtype Options = Options { command ::
  Command }` wrapper. We dropped it to match the kizamu `Kizamu.Cli` shape
  (also referenced by jitsurei's CLI patterns). EP-5 should follow the
  same shape when wiring its `kanji` subcommand: extend `commandParser`'s
  `hsubparser (...)` block with a new `command "kanji" (...)` entry that
  produces `CmdKanji <$> Kanji.parser`, and add a `runCommand (CmdKanji
  kc) = Kanji.runCommand kc` arm.

- **`argument` collides with `Control.Lens.Setter.argument`.** The prelude
  hides `argument` from its `Control.Lens` re-export so optparse-applicative
  parsers can use `argument` (and `strArgument`) unqualified. This is a
  cross-plan convention: any module mixing the prelude with optparse can
  rely on `argument` resolving to the optparse builder. If a module needs
  the lens setter it must `import Control.Lens (argument)` explicitly.

- **`import Nihongo.Prelude ()` (instances-only) is the established form
  for modules that don't use a prelude re-export.** Discovered while
  writing EP-2's `Nihongo.Kanji.KanjiVg`, which only uses base-Prelude
  names. EP-1's own `Nihongo.Cli.Completions` already follows this
  pattern. EP-3, EP-4, EP-5 should default to the empty-list import in
  modules that don't reference lens, generic-lens labels, `Generic`,
  unqualified `Text`, aeson helpers, etc., or `-Wall` will flag the open
  import as redundant.

- **Hiding subcommands needs `internal` (not `hidden`) at the
  `Mod CommandFields` level, in a separate `hsubparser` joined by `<|>`.**
  EP-2's plan called for `internal` on the `InfoMod` of a single command;
  that does not type-check (`internal :: Mod f a` is polymorphic but
  `InfoMod` is its own type). `hidden` only suppresses the brief usage
  line — it leaves the command listed under "Available commands:". The
  pattern that fully hides is:

      hsubparser ( ...public commands... )
        <|>
        hsubparser ( commandGroup "internal:" <> internal <> command "..." (...) )

  EP-5 must use the same idiom for any hidden subcommands it introduces.

- **KanjiVG release tag `r20250816` resolves to commit `bd13ffbcc`, not
  the `544d319f` originally cited in the EP-2 Decision Log.** That hash
  was the user's clone's `master` HEAD, not the tag itself. EP-3/EP-5
  should reference the tag (`r20250816`) for stability rather than
  paste a commit hash.

- **`xml-conduit` does not honour DTD `#FIXED` ATTLIST defaults when
  resolving namespaces.** KanjiVG declares `xmlns:kvg` only as a DTD
  default, so attributes parse with `namePrefix = Just "kvg"` but
  `nameNamespace = Nothing`. EP-3's plan called for matching by URL
  (`Just "http://kanjivg.tagaini.net"`) which never matches anything;
  EP-3's parser was corrected to match by prefix only. EP-5 must use
  the same prefix-only shape if it ever inspects KanjiVG attributes
  directly. Recorded in EP-3's Surprises and Decision Log.

- **`Nihongo.Prelude` re-exports `Control.Lens.Indexed.<.>`, which
  collides with `System.FilePath.<.>`.** Discovered while writing
  EP-4's `Nihongo.Terminal.Image`. The robust local fix is
  `import System.FilePath qualified as FP` and use `FP.</>` / `FP.<.>`
  at call sites, *not* hiding `<.>` from the prelude (which would
  break lens consumers). EP-5 should follow the same idiom for any
  filepath operations.

- **Visual rendering of inline images cannot be self-verified by an
  agent harness running headlessly inside tmux.** `Nihongo.Terminal.Image`
  emits the spec-shaped tmux-wrapped Kitty graphics escape, verified by
  `cat -A` (`\\ePtmux;\\e\\e_Ga=T,f=100,t=f,r=12;<base64-path>\\e\\\\`),
  but whether the user's outer terminal actually paints the kanji
  depends on the terminal supporting Kitty graphics *and* tmux
  passthrough being enabled (`set -g allow-passthrough on`). EP-5's
  end-to-end manual verification milestone has to be performed by the
  user, not by the implementing agent.


## Decision Log

- Decision: Source the KanjiVG corpus via `git submodule add` rather than fetching at
  build time or vendoring.
  Rationale: The user already has a clean clone at `/Users/shinzui/Keikaku/hub/kanjivg`
  pinned to release tag `r20250816`; a submodule reproduces that pinning across
  contributors and avoids licensing concerns about shipping the SVGs in our own repo
  (KanjiVG is CC-BY-SA 3.0 — distributable, but a submodule keeps the boundary clear).
  Date: 2026-05-05.

- Decision: Require `rsvg-convert` (from `librsvg`) as a system tool rather than rendering
  SVGs in pure Haskell.
  Rationale: The user explicitly approved this in conversation. Pure-Haskell SVG
  rasterization options are immature; `rsvg-convert` is widely packaged in nixpkgs and
  produces clean PNGs that the Kitty graphics protocol consumes via `f=100,t=f`. The
  same author's `kizamu` project already follows the "shell out via `System.Process`"
  pattern for similar concerns, so this matches existing conventions.
  Date: 2026-05-05.

- Decision: Support only the Kitty graphics protocol for image rendering in v1.
  Rationale: `kizamu` (same author, same conventions) supports only Kitty graphics
  with tmux passthrough and falls back to a `[Image: alt]` placeholder elsewhere; this
  gives us a one-protocol surface to test, free tmux support, and coverage for the
  user's own daily-driver terminal stack (Kitty/WezTerm/Ghostty). Sixel and iTerm2
  inline images can be added later if a user needs them.
  Date: 2026-05-05.

- Decision: Place the stroke order parser (EP-3) in `nihongo-core` and the image
  rendering (EP-4) in `nihongo-cli`.
  Rationale: The parser is pure, deterministic, and independent of any terminal
  concern; future non-CLI consumers (a TUI, a web view) will want it. Image rendering
  is inherently terminal-specific and depends on `System.Process` plus filesystem
  caching, both of which are CLI concerns.
  Date: 2026-05-05.

- Decision: Decompose into 5 child plans (foundations, submodule, parser, image,
  command) rather than fewer larger plans or more granular ones.
  Rationale: Each plan produces a behavior that can be demonstrated in isolation
  (foundations: `nihongo --version` works; submodule: `findStrokeSvg` returns the
  right path; parser: golden-test fixtures pass; image: a hand-fed PNG renders;
  command: end-to-end). Merging any pair would create a plan where two unrelated
  failures could land together; splitting any further would produce plans whose only
  artifact is a single function.
  Date: 2026-05-05.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision.

(To be filled during and after implementation.)
