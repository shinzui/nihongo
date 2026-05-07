---
id: 11
slug: add-user-defined-command-aliases-via-kdl-config
title: "Add user-defined command aliases via KDL config"
kind: exec-plan
created_at: 2026-05-07T03:27:13Z
intention: "intention_01kr04q2ajep5swkyba0vdjmyb"
---

# Add user-defined command aliases via KDL config

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The `nihongo` command-line tool today exposes a small fixed set of subcommands
(`hello`, `help`, `completions`, `kanji show`, `kanji png`). Users who reach for
the same long invocation many times a day — for example `nihongo kanji show 漢` —
have no shorter way to type it. After this change a user can drop a small KDL
("Cuddly Data Language") file at `$XDG_CONFIG_HOME/nihongo/config.kdl` (which
defaults to `~/.config/nihongo/config.kdl` on Linux and macOS) containing:

    aliases {
      ks "kanji show"
      kp "kanji png"
      h  "help"
    }

and immediately use the short forms:

    $ nihongo ks 漢       # behaves exactly like `nihongo kanji show 漢`
    $ nihongo kp 漢       # behaves exactly like `nihongo kanji png 漢`
    $ nihongo h            # behaves exactly like `nihongo help`

A new inspection subcommand `nihongo alias list` prints the resolved alias map
in a sorted, padded `name = expansion` table so the user can verify what their
config actually produced:

    $ nihongo alias list
    h  = help
    kp = kanji png
    ks = kanji show

Built-in commands (`hello`, `help`, `completions`, `kanji`, `alias`) cannot be
shadowed: an alias named `kanji` is silently ignored at expansion time. Argv
whose first token starts with `-` (so `--version`, `--help`, and the
`--bash-completion-index …` shell-completion entry path) is also left alone, so
users cannot accidentally break completion or version printing by editing their
config.

The aliases are loaded once at process start, expanded against the raw argv
**before** `optparse-applicative` parses, and the binary then proceeds exactly
as if the user had typed the long form. Expansion is non-recursive: `tw` →
`kanji show 漢` works, but `a` → `b foo` plus `b` → `c bar` produces `b foo …`,
not `c bar foo …`.

The change touches both packages but is small in surface area:

  * `nihongo-core/src/Nihongo/Config/Types.hs` — new module, defines the
    `NihongoConfig` and `AliasesSection` records (parse model only; resolution
    is a separate concern).
  * `nihongo-core/src/Nihongo/Config/Load.hs` — new module, KDL decoder and
    XDG-aware loader; returns `Either ConfigError NihongoConfig`.
  * `nihongo-cli/src/Nihongo/Cli/Aliases.hs` — new module, the pure
    `expandAlias` function and the `builtinCommands` registry.
  * `nihongo-cli/src/Nihongo/Cli/Alias.hs` — new module, the `nihongo alias
    list` subcommand (parser + handler + `renderAliasTable` helper).
  * `nihongo-cli/src/Nihongo/Cli.hs` — wire alias expansion into `runCli` and
    register the new `alias` top-level command.
  * `nihongo-cli/help/aliases.md` — new help topic explaining the schema,
    precedence, and built-in protection. Registered in `Nihongo.Cli.Help`.
  * `nix/haskell-overlay.nix` — add `kdl-hs` from Hackage (nixpkgs ships
    0.2.1; the API used here lives in 1.0+).
  * `nihongo-core.cabal` and `nihongo-cli.cabal` — add the new modules and the
    `kdl-hs ^>=1.0` dependency.

The reference design lives at
`/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/cli/command-aliases-kdl.md`
(read end-to-end before starting); this plan is the nihongo-specific
adaptation. The two existing in-tree adopters of the pattern are
`/Users/shinzui/Keikaku/bokuno/notion-cli` and
`/Users/shinzui/Keikaku/bokuno/mina` — `mina` is the closest match
because it uses the cleaner `aliases { … }` section name and is also a
multi-package repo with a Nix-driven Haskell build, like nihongo.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be
documented here, even if it requires splitting a partially completed task into
two ("done" vs. "remaining"). This section must always reflect the actual
current state of the work.

- [x] Read the reference at
      `/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/cli/command-aliases-kdl.md`
      end-to-end and skim the mina implementation files listed in **Context and
      Orientation** so the design is internalised before editing. (2026-05-06)
- [x] Milestone 1 — Add the `kdl-hs` dependency to the Nix overlay and the two
      cabal files; create the `Nihongo.Config.Types` and `Nihongo.Config.Load`
      modules with just the alias-decoding shape; add a one-test sanity check
      that `decodeWith aliasesSectionDecoder "aliases { tw \"kanji show\" }"`
      yields the expected `Map`. (2026-05-06)
- [x] Milestone 2 — Add the pure `Nihongo.Cli.Aliases` module
      (`expandAlias` + `builtinCommands`). Add a unit-test module
      `Test/Nihongo/Cli/AliasesSpec.hs` covering empty argv, dash bypass,
      built-in shadowing, single-pass expansion, and trailing-arg append.
      (2026-05-06)
- [x] Milestone 3 — Wire alias expansion into `Nihongo.Cli.runCli`. Replace
      the bare `execParser` call with the `getArgs → expandRawArgs →
      execParserPure → handleParseResult` sequence. Demonstrate
      `nihongo ks 漢` working end-to-end with a hand-written config under
      `XDG_CONFIG_HOME=$(mktemp -d)`. (2026-05-06)
- [x] Milestone 4 — Add the `nihongo alias list` subcommand
      (`Nihongo.Cli.Alias`), register it in `commandParser`, add it to
      `builtinCommands`, and add a `nihongo-cli/help/aliases.md` topic
      registered in `Nihongo.Cli.Help.helpTopics`. Extend the test module
      to cover `renderAliasTable` and assert the parser accepts every name in
      `builtinCommands`. (2026-05-06)
- [ ] Milestone 5 — End-to-end smoke test in a real shell using a real
      `~/.config/nihongo/config.kdl` (or an `XDG_CONFIG_HOME` override)
      following the script in **Validation and Acceptance**. Capture the
      transcript here and in **Surprises & Discoveries** if anything diverges.
- [ ] Final commit and Outcomes & Retrospective entry.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered
during implementation. Provide concise evidence.

- 2026-05-06 (Milestone 1): The plan's `resolveAliases =
  maybe Map.empty (.aliasMap) . (.aliases)` requires
  `OverloadedRecordDot`, which mina enables via its cabal common-options
  but nihongo does not (nihongo's existing idiom is generic-lens labels,
  e.g. `topic ^. #topicName`). Replaced with the equivalent
  `maybe Map.empty aliasMap . aliases` using plain field selectors —
  works because `aliases` and `aliasMap` field names do not collide
  anywhere else in the two packages. No extension change needed.
- 2026-05-06 (Milestone 1): `nihongo-core/nihongo-core.cabal`'s
  `test-suite` stanza did not previously list `containers`. Added it
  because `Test.Nihongo.Config.LoadSpec` imports `Data.Map.Strict`. The
  plan's Step 2 only mentioned cabal additions for the library stanza
  and missed this test-suite dependency.
- 2026-05-06 (Milestone 2): `nihongo-cli/nihongo-cli.cabal`'s library
  stanza was missing `containers` (and so was the test stanza). Added
  `containers ^>=0.7` to both. The plan's "no new top-level
  build-depends" claim in **Interfaces and Dependencies** was wrong:
  while `text` and `optparse-applicative` were already present,
  `Data.Map.Strict` was new to the CLI package.
- 2026-05-06 (Milestone 3): Step 4 of **Concrete Steps** specifies
  rendering `KDL.DecodeError` via `show`, claiming "show is what mina
  uses today". This is incorrect — `mina-core/src/Mina/Config/Load.hs`
  uses `KDL.renderDecodeError`. The smoke test confirmed the `show`
  output is genuinely poor (it dumps the `DecodeError` record literal:
  `DecodeError {filepath = Nothing, errors = [([],DecodeError_ParseError
  "...")]}`). Switched to `KDL.renderDecodeError`, which the plan
  itself authorised: "If the rendered output reads poorly we can swap
  in a custom renderer later." Output is now a clean parser
  diagnostic with line/column. No new dependency required;
  `KDL.renderDecodeError` is already in `kdl-hs`.
- 2026-05-06 (Milestone 4): The plan's Step 2 listed a hypothetical
  `Nihongo.Config` re-export shim "added in Milestone 4 only if it
  makes the imports in `Nihongo.Cli` cleaner". It did not — both
  `Nihongo.Cli` and `Nihongo.Cli.Alias` import directly from
  `Nihongo.Config.Load` and `Nihongo.Config.Types` cleanly. Skipped.
- 2026-05-06 (Milestone 4): The plan's Step 10 spec extension imported
  `HelpTopic (..)` for pattern-matching, but the test uses
  `(^. #topicName)` and `(^. #topicContent)` (lens labels) and never
  pattern-matches the constructor. The constructor import is unused
  and triggers `-Wunused-imports`; trimmed to `helpTopics` only.
- 2026-05-06 (Milestone 4): The CLI test stanza in
  `nihongo-cli/nihongo-cli.cabal` previously did not list
  `nihongo-core` or `optparse-applicative`. Both became necessary in
  M4 because `Test.Nihongo.Cli.AliasesSpec` imports `Nihongo.Prelude`
  (for the lens labels) and `Options.Applicative` (for the
  `execParserPure` registry test). Plan's Step 2 listed only the
  module additions, not these new test-suite dependencies.


## Decision Log

Record every decision made while working on the plan.

- Decision: Use the section name `aliases { … }` (mina's convention), not
  `command-alias { … }` (notion-cli's convention).
  Rationale: nihongo has no namespace collision (no pre-existing `alias`
  feature). The reference document recommends the shorter name when the
  namespace is free.
  Date: 2026-05-06

- Decision: Put `expandAlias` and `builtinCommands` in
  `nihongo-cli/src/Nihongo/Cli/Aliases.hs` (the CLI package), but put the
  KDL parse model and loader in `nihongo-core` (`Nihongo.Config.Types` and
  `Nihongo.Config.Load`).
  Rationale: The expander depends on `optparse-applicative`'s notion of
  "argv before parsing" so it belongs with the CLI parser. The config types
  and KDL decoding are pure data-model concerns and have no CLI dependency,
  so they fit with the rest of `nihongo-core`. This mirrors mina's
  layout (`Mina.Config.*` in core, `Mina.CLI.Aliases` in cli).
  Date: 2026-05-06

- Decision: XDG-only config for now — load from
  `$XDG_CONFIG_HOME/nihongo/config.kdl` (defaulting to
  `~/.config/nihongo/config.kdl`); no per-project override file in this
  iteration.
  Rationale: nihongo has no other config concept yet, and adding a
  project-local file (à la mina's `mina.kdl`) doubles the load + merge
  surface for no concrete user need today. The merge pattern from the
  reference doc can be added later without breaking the schema.
  Date: 2026-05-06

- Decision: A missing config file is **not** an error — it is silently
  treated as "no aliases configured", and the CLI proceeds normally.
  Rationale: Until a user explicitly opts into aliases, the binary should
  behave exactly as it does today. This matches the reference design's
  "forgiving config loader" guidance.
  Date: 2026-05-06

- Decision: A *malformed* config file IS an error. Print a one-line message
  to stderr (`nihongo: config error: …`) and exit non-zero, but only when
  the user actually invoked something that needed the alias map (i.e. a
  non-built-in, non-dash first token). For built-in subcommands, the
  malformed file is ignored so the user can keep using `nihongo` while they
  fix it.
  Rationale: Matches mina's `expandRawArgs` behaviour. A broken file
  should be visible the moment the user expects an alias to fire, but
  should never block `nihongo --version`, `nihongo help`, or shell
  completion (which is what makes `--help` debuggable).
  Date: 2026-05-06

- Decision: Pull `kdl-hs` from Hackage (1.0.1) via the existing
  `callCabal2nix` overlay pattern in `nix/haskell-overlay.nix`, not via a
  shared `haskell-nix` registry entry.
  Rationale: The shared registry at
  `/Users/shinzui/Keikaku/bokuno/haskell-nix/overlays/registry.nix` does
  not have `kdl-hs` yet; mina handles it the same way locally
  (see `/Users/shinzui/Keikaku/bokuno/mina/nix/haskell-overlay.nix`
  lines 8-15). When the registry adopts kdl-hs, both projects can drop
  their local override.
  Date: 2026-05-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at
completion. Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section orients a reader who has only this plan and the working tree.
Skip ahead if you already know the codebase.

### What nihongo is

nihongo is a small Haskell command-line tool whose binary is named
`nihongo`. It ships from a Cabal multi-package repository at
`/Users/shinzui/Keikaku/bokuno/nihongo` with two packages:

  * `nihongo-core` — pure library; today exports `Nihongo.Prelude` and the
    KanjiVG stroke-order types under `Nihongo.Kanji.*`. This is where the
    new config parse-model and loader will live.
  * `nihongo-cli` — application package; ships the `nihongo` executable.
    This is where the CLI parser (`Nihongo.Cli`), help-topic browser
    (`Nihongo.Cli.Help`), shell completions (`Nihongo.Cli.Completions`),
    and the new alias-expansion code will live.

The build is driven by `cabal.project` at the repo root. The Nix flake
(`flake.nix`) lays a Haskell overlay over nixpkgs' `ghc9122` package set;
project-local Haskell-package overrides live in
`nix/haskell-overlay.nix`. The shared overlay at
`/Users/shinzui/Keikaku/bokuno/haskell-nix` provides cross-project
patches but does **not** currently include `kdl-hs`, so we override it
locally (see Decision Log).

### Today's CLI structure

`nihongo-cli/src/Nihongo/Cli.hs` defines the parser tree:

    data Command
      = CmdHello !(Maybe Text)
      | CmdHelp !Help.HelpCommand
      | CmdCompletions !Completions.CompletionsShell
      | CmdKanji !Kanji.KanjiCommand

    runCli :: IO ()
    runCli = do
      cmd <- execParser parserInfo
      runCommand cmd

After this plan, `runCli` will load the config first, expand the argv,
and call `execParserPure` instead of `execParser`. The `Command` ADT
gains one constructor (`CmdAlias !Alias.AliasCommand`).

### What KDL is and what kdl-hs gives us

KDL ("KDL Document Language", spec at <https://kdl.dev>) is a
human-friendly, brace-and-newline-structured config format. A KDL
*document* is a sequence of *nodes*. Each node has a *name* (an
identifier), zero or more *positional arguments* (called *args* in
kdl-hs), zero or more named *properties* (`key=value`), and an optional
*children* block delimited by `{ … }`. Example:

    aliases {
      ks "kanji show"
    }

Here the outer node is named `aliases`, has no args, no properties, and
one child node named `ks` whose first arg is the string `"kanji show"`.

The Haskell parser is **kdl-hs ≥ 1.0** (the Hackage tarball is
fetched via the Nix overlay; the source is in
`/Users/shinzui/Keikaku/hub/kdl-hs-project/kdl-hs` for reading). The
APIs we use are all re-exported from the top-level module `KDL`:

  * `KDL.decodeFileWith :: DocumentDecoder a -> FilePath -> IO (Either DecodeError a)`
    reads a file and decodes it.
  * `KDL.document :: NodeListDecoder a -> DocumentDecoder a` finalises a
    node-list decoder so unknown top-level nodes raise an error
    (exactly what we want — typos in the user's config should be
    caught).
  * `KDL.optional :: Alternative f => f a -> f (Maybe a)` (re-exported from
    `Control.Applicative`).
  * `KDL.node :: DecodeNode a => Text -> NodeListDecoder a` decodes the
    first child node with the given name using its `DecodeNode` instance.
  * `KDL.children :: NodeListDecodeArrow a b -> NodeDecodeArrow a b`
    descends into the `{ … }` block of the node currently being decoded.
  * `KDL.remainingNodesWith :: Typeable b => NodeDecodeArrow a b ->
    NodeListDecodeArrow a (Map Text [b])` consumes **every** child node
    regardless of name, decoding each with the supplied node decoder
    and grouping by node name. This is the combinator that lets us
    treat each child node's name as the alias key.
  * `KDL.arg :: DecodeValue a => NodeDecoder a` decodes the next
    positional argument of the current node.

For each repeated node name, `remainingNodesWith` produces a list whose
**head is the most recently declared occurrence** (it builds with
`Map.fromListWith (<>)` after a left-to-right walk that prepends each
hit); we collapse with `Data.Maybe.listToMaybe` so the most recent value
wins, matching the existing `Mina.Config.Types.AliasesSection` decoder.

### The reference document

`/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/cli/command-aliases-kdl.md`
is the canonical specification of this pattern. Read it end-to-end before
making any edits — every decision in this plan ties back to it. The two
in-tree adopters listed in its "Known Implementations" section are:

  * `/Users/shinzui/Keikaku/bokuno/mina` — closest analogue. Files
    to read first:
      * `mina-core/src/Mina/Config/Types.hs:71-74` (the
        `AliasesSection` record).
      * `mina-core/src/Mina/Config/Load.hs:598-604` (the
        `DecodeNode AliasesSection` instance).
      * `mina-core/src/Mina/Config/Load.hs:515-522` (the top-level
        document decoder embedding the optional `aliases` node).
      * `mina-cli/src/Mina/CLI/Aliases.hs` (the pure expander).
      * `mina-cli/src/Mina/CLI/Alias.hs` (the `mina alias list`
        subcommand and `renderAliasTable`).
      * `mina-cli/src/Mina/CLI/Commands.hs:64-100` (the `runCli` +
        `expandRawArgs` integration).
      * `mina-cli/test/Mina/CLI/AliasSpec.hs` (the test pattern we
        will adapt).
      * `nix/haskell-overlay.nix:8-15` (the Hackage tarball pin).
  * `/Users/shinzui/Keikaku/bokuno/notion-cli` — uses
    `command-alias { alias "<name>" "<expansion>" }` shape; informative
    but not the shape we are adopting. The relevant module is
    `notion-cli-exe/src/NotionCli/CommandAlias.hs`.


## Plan of Work

The work is split into five milestones. Each ends with a working build and a
green test suite. Commit after each milestone with a Conventional Commit
message and the two trailers from the **Idempotence and Recovery** section.

### Milestone 1 — Wire kdl-hs into the build and decode an `aliases` block

**Scope.** Add the `kdl-hs` dependency, create the two new core modules
(`Nihongo.Config.Types` and `Nihongo.Config.Load`), and prove a single
KDL string decodes into a `Map Text Text`. No CLI changes, no expansion,
no IO yet.

**What will exist at the end.**

  * `nix/haskell-overlay.nix` declares `kdl-hs` from a Hackage tarball.
  * `nihongo-core.cabal` lists `kdl-hs ^>=1.0`, `containers ^>=0.7`, and
    the two new modules.
  * `nihongo-core/src/Nihongo/Config/Types.hs` exports
    `NihongoConfig (..)`, `AliasesSection (..)`, and `ConfigError (..)`.
  * `nihongo-core/src/Nihongo/Config/Load.hs` exports
    `nihongoConfigDecoder :: KDL.DocumentDecoder NihongoConfig`,
    `decodeNihongoConfig :: Text -> Either ConfigError NihongoConfig`,
    and `loadNihongoConfig :: IO (Either ConfigError NihongoConfig)`.
  * `nihongo-core/test/Test/Nihongo/Config/LoadSpec.hs` exercises
    `decodeNihongoConfig` against three small KDL strings (empty doc;
    one alias; two aliases including a within-file duplicate, asserting
    last-wins).

**Acceptance.** From the repo root, both of these succeed:

    cabal build all
    cabal test nihongo-core-tests

The new test file's three cases all pass.

### Milestone 2 — Pure expander and registry

**Scope.** Add `Nihongo.Cli.Aliases` to `nihongo-cli` (the pure module that
mina's `Mina.CLI.Aliases` provides) and a unit-test module covering the
six behaviours of the expander.

**What will exist at the end.**

  * `nihongo-cli/src/Nihongo/Cli/Aliases.hs` exports
    `builtinCommands :: [Text]` and
    `expandAlias :: Map Text Text -> [String] -> [String]`.
  * `nihongo-cli/test/Test/Nihongo/Cli/AliasesSpec.hs` exists and is
    registered in `nihongo-cli/test/Main.hs`. It asserts: empty argv ⇒
    empty argv; dash-prefixed first token left alone; built-in name in
    map left alone; single-token alias expands and appends remaining
    args; alias values are not recursively re-expanded; first token
    that is neither alias nor built-in is left alone; whitespace in
    expansion is split via `Data.Text.words`.
  * `builtinCommands` lists exactly the names this milestone knows
    about: `["hello", "help", "completions", "kanji"]`. The
    `"alias"` name is added in Milestone 4 alongside the new
    subcommand registration; doing it now would lie about the
    parser's actual surface.

**Acceptance.** `cabal test nihongo-cli-test` passes; the new spec
contributes the seven `it` blocks.

### Milestone 3 — Wire the expander into `runCli`

**Scope.** Replace `execParser` in `Nihongo.Cli.runCli` with the explicit
sequence and prove that `nihongo ks` runs the same code path as
`nihongo kanji show` when the config has the alias.

**What will exist at the end.**

  * `nihongo-cli/src/Nihongo/Cli.hs` now reads `getArgs`, calls a new
    helper `expandRawArgs :: [String] -> IO [String]` (defined in the
    same module — the implementation is small enough not to warrant its
    own module), and feeds the result to
    `execParserPure (prefs showHelpOnEmpty) parserInfo`. The
    `runCommand` dispatcher is unchanged.
  * `expandRawArgs` mirrors mina's: pass-through for empty argv,
    dash-prefixed first token, or first token in `builtinCommands`.
    Otherwise it calls `Nihongo.Config.Load.loadNihongoConfig`; on
    `Left err` it prints `nihongo: config error:\n  …` to stdout (or
    stderr — see the implementation choice in **Concrete Steps**) and
    `exitWith (ExitFailure 1)`. On `Right cfg` it returns
    `expandAlias (resolveAliases cfg) args`.
  * A new helper `resolveAliases :: NihongoConfig -> Map Text Text` is
    defined alongside `nihongoConfigDecoder` in `Nihongo.Config.Load`
    and simply unwraps the optional `AliasesSection` (or returns
    `Map.empty`).
  * Adding `prefs showHelpOnEmpty` is a behaviour change worth flagging
    in the commit body: today, bare `nihongo` errors with "Missing
    command"; after the change, bare `nihongo` prints the top-level
    help. This matches mina's behaviour and is what users intuitively
    expect when an alias is misspelled.

**Acceptance.** With `XDG_CONFIG_HOME` pointing at a tmp dir containing
`nihongo/config.kdl` with `aliases { ks "kanji show" }`, both of these
print the same first line of stroke-order output:

    nihongo kanji show 漢
    nihongo ks 漢

And a malformed config produces a single error line:

    $ nihongo ks
    nihongo: config error:
      <decode error message>
    $ echo $?
    1

While built-ins keep working even with the broken file:

    $ nihongo --version
    nihongo 0.1.0.0 (<git-hash>)

### Milestone 4 — `nihongo alias list` and the help topic

**Scope.** Add the inspection subcommand and the documentation topic.
Update `builtinCommands` to include `"alias"` so a user cannot define an
alias named `alias` and shadow it.

**What will exist at the end.**

  * `nihongo-cli/src/Nihongo/Cli/Alias.hs` exports
    `AliasCommand (..)`, `aliasCommandParser :: Parser AliasCommand`,
    `handleAliasCommand :: AliasCommand -> IO ()`, and
    `renderAliasTable :: Map Text Text -> Text`.
    Implementation is the obvious port of mina's; the only material
    difference is the error-message prefix (`"nihongo: …"` instead of
    `"mina: …"`).
  * `nihongo-cli/src/Nihongo/Cli.hs` registers the new command in
    `commandParser` (via `command "alias" …`) and dispatches to
    `Alias.handleAliasCommand` from `runCommand`. The `Command`
    constructor `CmdAlias !Alias.AliasCommand` is added.
  * `Nihongo.Cli.Aliases.builtinCommands` is updated to
    `["hello", "help", "completions", "kanji", "alias"]`.
  * `nihongo-cli/help/aliases.md` is created and registered in
    `Nihongo.Cli.Help.helpTopics` exactly the way the existing topics
    are: a `HelpTopic "aliases" "Configuring command aliases"
    $(embedStringFile "help/aliases.md")` entry. The body covers
    schema, file location, precedence (within-file last-wins),
    built-in protection, dash bypass, and the `nihongo alias list`
    inspection command. See the **Concrete Steps** section for the
    exact body.
  * `Test/Nihongo/Cli/AliasesSpec.hs` is extended with three more
    sections: (a) `renderAliasTable` empty / single / padded /
    sorted; (b) every name in `builtinCommands` is accepted by the
    parser when given `["<name>", "--help"]` (use the same trick mina
    uses with `execParserPure runCliParserInfo`); (c) an unknown
    top-level command name produces a `Failure`.
  * `Nihongo.Cli` exports a new `runCliParserInfo :: ParserInfo
    Command` so the test can call `execParserPure` without invoking
    `runCli` itself. (This export is the smallest change that makes
    the registry test possible; mina does the same.)

**Acceptance.** From the repo root:

    cabal test all                                     # all suites green
    nihongo alias list                                 # prints the table
    nihongo help aliases                               # prints the topic body
    nihongo alias list | head -1                       # same first row as below
    XDG_CONFIG_HOME=/tmp/nihongo-test nihongo alias list  # honors the override

### Milestone 5 — End-to-end smoke test

**Scope.** No code changes. Run the script in **Validation and
Acceptance** in a real Bash and a real Zsh session against an installed
binary, and record the transcript here and (if anything diverges) in
**Surprises & Discoveries**.


## Concrete Steps

Every command runs from the repo root (`/Users/shinzui/Keikaku/bokuno/nihongo`)
unless noted otherwise.

### Step 0 — Prerequisites and pre-flight

Confirm the dev shell is active (the prompt should say `(nix:default)` or
similar — `direnv` handles this automatically because the repo has an
`.envrc`). Run:

    cabal build all
    cabal test all

Both should succeed today, before any edits.

### Step 1 — Add kdl-hs to the Nix overlay

Edit `nix/haskell-overlay.nix`. Insert the `kdl-hs` block at the top of
the overlay record, immediately after `final: prev: {`. The block is
copied near-verbatim from
`/Users/shinzui/Keikaku/bokuno/mina/nix/haskell-overlay.nix:8-15`:

    # kdl-hs 1.0.1 is not yet in nixpkgs (which ships 0.2.1). Fetch from
    # Hackage directly until the shared haskell-nix registry adopts it.
    kdl-hs = pkgs.haskell.lib.compose.dontCheck
      (pkgs.haskell.lib.compose.doJailbreak (final.callCabal2nix "kdl-hs"
        (builtins.fetchTarball {
          url = "https://hackage.haskell.org/package/kdl-hs-1.0.1/kdl-hs-1.0.1.tar.gz";
          sha256 = "sha256-XlNHId1y8i9OIjId09/W8oup+8Ma+bi6WkmR7MgDqSg=";
        })
        { }));

(The local `inherit (pkgs.haskell.lib.compose) doJailbreak;` line at the
top of `haskell-overlay.nix` already provides `doJailbreak`; if you
prefer, also add `dontCheck` to that `inherit` line and drop the
`pkgs.haskell.lib.compose.` prefixes above. Functionally equivalent.)

### Step 2 — Add the dependency to the cabal files

In `nihongo-core/nihongo-core.cabal`, library stanza, add `kdl-hs ^>=1.0`
to the alphabetised `build-depends` list (just after `generic-lens,`).
In the same stanza, append two new modules to `exposed-modules`:

    Nihongo.Config.Load
    Nihongo.Config.Types

In the `test-suite nihongo-core-tests` stanza, add a new entry to
`other-modules`:

    Test.Nihongo.Config.LoadSpec

In `nihongo-cli/nihongo-cli.cabal`, library stanza, append three new
modules to `exposed-modules`:

    Nihongo.Cli.Alias
    Nihongo.Cli.Aliases
    Nihongo.Config

(The third — `Nihongo.Config` — is just a re-export shim added in
Milestone 4 only if it makes the imports in `Nihongo.Cli` cleaner; if
not needed, omit it.)

In the `test-suite nihongo-cli-test` stanza, add to `other-modules`:

    Test.Nihongo.Cli.AliasesSpec

### Step 3 — Define `Nihongo.Config.Types`

Create `nihongo-core/src/Nihongo/Config/Types.hs`:

    -- | Parse model and error type for the nihongo KDL config file.
    --
    -- Today the only top-level section is @aliases { … }@; the type is
    -- shaped to allow more sections later without breaking the schema.
    module Nihongo.Config.Types
      ( NihongoConfig (..),
        AliasesSection (..),
        ConfigError (..),
      )
    where

    import Data.Map.Strict (Map)
    import Nihongo.Prelude

    data NihongoConfig = NihongoConfig
      { aliases :: !(Maybe AliasesSection)
      }
      deriving stock (Generic, Show, Eq)

    -- | Each child node's name is the alias key; its first positional
    -- argument is the expansion. Within-file duplicates collapse to the
    -- last occurrence.
    newtype AliasesSection = AliasesSection
      { aliasMap :: Map Text Text
      }
      deriving stock (Generic, Show, Eq)

    data ConfigError
      = ConfigParseError !Text
      | ConfigFileReadError !FilePath !Text
      deriving stock (Generic, Show, Eq)

### Step 4 — Define `Nihongo.Config.Load`

Create `nihongo-core/src/Nihongo/Config/Load.hs`:

    -- | KDL decoder and XDG-aware loader for the nihongo config file.
    --
    -- The config lives at @\$XDG_CONFIG_HOME/nihongo/config.kdl@
    -- (defaults to @~/.config/nihongo/config.kdl@ on macOS / Linux).
    -- A missing file is not an error — the loader returns an empty
    -- 'NihongoConfig'. A malformed file is an error.
    module Nihongo.Config.Load
      ( loadNihongoConfig,
        decodeNihongoConfig,
        nihongoConfigDecoder,
        resolveAliases,
        configFilePath,
      )
    where

    import Control.Exception (try)
    import Data.Map.Strict (Map)
    import Data.Map.Strict qualified as Map
    import Data.Maybe (listToMaybe)
    import Data.Text qualified as Text
    import Data.Text.IO qualified as TIO
    import KDL qualified
    import Nihongo.Config.Types
    import Nihongo.Prelude
    import System.Directory (XdgDirectory (..), doesFileExist, getXdgDirectory)
    import System.FilePath ((</>))

    configFilePath :: IO FilePath
    configFilePath = getXdgDirectory XdgConfig ("nihongo" </> "config.kdl")

    loadNihongoConfig :: IO (Either ConfigError NihongoConfig)
    loadNihongoConfig = do
      path <- configFilePath
      exists <- doesFileExist path
      if not exists
        then pure (Right (NihongoConfig Nothing))
        else do
          readResult <- try @IOError (TIO.readFile path)
          case readResult of
            Left e -> pure (Left (ConfigFileReadError path (Text.pack (show e))))
            Right contents -> pure (decodeNihongoConfig contents)

    decodeNihongoConfig :: Text -> Either ConfigError NihongoConfig
    decodeNihongoConfig =
      first (ConfigParseError . Text.pack . show) . KDL.decodeWith nihongoConfigDecoder
      where
        first f = either (Left . f) Right

    nihongoConfigDecoder :: KDL.DocumentDecoder NihongoConfig
    nihongoConfigDecoder = KDL.document $ do
      a <- KDL.optional (KDL.node @AliasesSection "aliases")
      pure NihongoConfig { aliases = a }

    instance KDL.DecodeNode AliasesSection where
      nodeDecoder = KDL.children $ do
        rawMap <- KDL.remainingNodesWith (KDL.arg @Text)
        pure AliasesSection { aliasMap = Map.mapMaybe listToMaybe rawMap }

    resolveAliases :: NihongoConfig -> Map Text Text
    resolveAliases = maybe Map.empty (.aliasMap) . (.aliases)

Notes:

  * `KDL.decodeWith` returns `Either KDL.DecodeError NihongoConfig`. We
    render the error via `show` (kdl-hs's `Show` instance produces a
    multi-line message that already names the source location). If the
    rendered output reads poorly we can swap in a custom renderer
    later — but `show` is what mina uses today.
  * The `import qualified Data.Text as Text` and the local `first`
    helper avoid a transitive `bifunctors` dependency.
  * `XdgDirectory` and `getXdgDirectory` come from `directory ^>=1.3`
    which `nihongo-core.cabal` already lists.

### Step 5 — First sanity test for the decoder

Create `nihongo-core/test/Test/Nihongo/Config/LoadSpec.hs`:

    module Test.Nihongo.Config.LoadSpec (spec) where

    import Data.Map.Strict qualified as Map
    import Nihongo.Config.Load (decodeNihongoConfig, resolveAliases)
    import Test.Hspec

    spec :: Spec
    spec = describe "decodeNihongoConfig" $ do
      it "treats an empty document as no aliases" $
        case decodeNihongoConfig "" of
          Right cfg -> resolveAliases cfg `shouldBe` Map.empty
          Left e -> expectationFailure (show e)

      it "decodes a single aliases block with one entry" $
        case decodeNihongoConfig "aliases { ks \"kanji show\" }" of
          Right cfg ->
            resolveAliases cfg `shouldBe` Map.fromList [("ks", "kanji show")]
          Left e -> expectationFailure (show e)

      it "collapses within-file duplicates to the last occurrence" $
        case decodeNihongoConfig
               "aliases {\n  ks \"first\"\n  ks \"second\"\n}" of
          Right cfg ->
            Map.lookup "ks" (resolveAliases cfg) `shouldBe` Just "second"
          Left e -> expectationFailure (show e)

Wire it into `nihongo-core/test/Main.hs` (replacing the existing
`hspec`-only call so both specs run):

    module Main (main) where

    import Test.Hspec (hspec)
    import Test.Nihongo.Config.LoadSpec qualified as LoadSpec
    import Test.Nihongo.Kanji.StrokeOrderSpec qualified as StrokeOrderSpec

    main :: IO ()
    main = hspec $ do
      StrokeOrderSpec.spec
      LoadSpec.spec

Run:

    cabal build all
    cabal test nihongo-core-tests

Expected: all three new examples pass alongside the existing
`Nihongo.Kanji.StrokeOrder` spec.

### Step 6 — Add `Nihongo.Cli.Aliases` and its tests

Create `nihongo-cli/src/Nihongo/Cli/Aliases.hs`:

    -- | Pre-parse rewriting of argv to support user-defined command
    -- aliases declared in the @aliases { … }@ KDL block.
    --
    -- 'expandAlias' is pure; the loader and IO live in
    -- "Nihongo.Cli" and "Nihongo.Config.Load".
    module Nihongo.Cli.Aliases
      ( builtinCommands,
        expandAlias,
      )
    where

    import Data.Map.Strict (Map)
    import Data.Map.Strict qualified as Map
    import Data.Text (Text)
    import Data.Text qualified as T

    -- | Top-level subcommand names registered in 'Nihongo.Cli.commandParser'.
    -- Keep this list in sync when adding new commands; the test suite
    -- enforces both directions of the registry/parser correspondence.
    builtinCommands :: [Text]
    builtinCommands =
      [ "hello",
        "help",
        "completions",
        "kanji"
      ]

    expandAlias :: Map Text Text -> [String] -> [String]
    expandAlias aliasMap = \case
      [] -> []
      args@(first : rest)
        | startsWithDash first -> args
        | T.pack first `elem` builtinCommands -> args
        | otherwise -> case Map.lookup (T.pack first) aliasMap of
            Nothing -> args
            Just expansion -> map T.unpack (T.words expansion) <> rest
      where
        startsWithDash ('-' : _) = True
        startsWithDash _ = False

(Note: the module-export list omits anything else; the test imports the
two named identifiers only.)

Create `nihongo-cli/test/Test/Nihongo/Cli/AliasesSpec.hs`:

    module Test.Nihongo.Cli.AliasesSpec (spec) where

    import Data.Map.Strict qualified as Map
    import Nihongo.Cli.Aliases (builtinCommands, expandAlias)
    import Test.Hspec

    spec :: Spec
    spec = do
      describe "expandAlias" $ do
        it "returns [] for an empty argv" $
          expandAlias Map.empty [] `shouldBe` []

        it "leaves a flag-only argv unchanged (--version)" $
          expandAlias Map.empty ["--version"] `shouldBe` ["--version"]

        it "leaves a flag-only argv unchanged even when the flag name is in the alias map" $
          expandAlias (Map.fromList [("--help", "kanji show")]) ["--help"]
            `shouldBe` ["--help"]

        it "leaves built-in command argv unchanged" $
          expandAlias Map.empty ["kanji", "show", "漢"]
            `shouldBe` ["kanji", "show", "漢"]

        it "refuses to shadow a built-in command name with an alias" $
          expandAlias
            (Map.fromList [("kanji", "help")])
            ["kanji", "show", "漢"]
            `shouldBe` ["kanji", "show", "漢"]

        it "expands a single alias and appends remaining argv" $
          expandAlias
            (Map.fromList [("ks", "kanji show")])
            ["ks", "漢"]
            `shouldBe` ["kanji", "show", "漢"]

        it "does not recurse: alias values pass through verbatim" $
          expandAlias
            (Map.fromList [("a", "b foo"), ("b", "c bar")])
            ["a", "x"]
            `shouldBe` ["b", "foo", "x"]

        it "leaves argv unchanged when the first token is neither alias nor built-in" $
          expandAlias
            (Map.fromList [("ks", "kanji show")])
            ["unknown", "--json"]
            `shouldBe` ["unknown", "--json"]

        it "splits the expansion on whitespace via Data.Text.words" $
          expandAlias
            (Map.fromList [("multi", "  kanji   show  漢  ")])
            ["multi"]
            `shouldBe` ["kanji", "show", "漢"]

      describe "builtinCommands registry" $ do
        it "contains exactly the commands registered in commandParser today" $
          builtinCommands `shouldMatchList`
            ["hello", "help", "completions", "kanji"]

Wire it into `nihongo-cli/test/Main.hs`:

    module Main (main) where

    import Test.Hspec (hspec)
    import Test.Nihongo.Cli.AliasesSpec qualified as AliasesSpec
    import Test.Nihongo.Cli.CompletionsSpec qualified as CompletionsSpec

    main :: IO ()
    main = hspec $ do
      CompletionsSpec.spec
      AliasesSpec.spec

Run:

    cabal build all
    cabal test nihongo-cli-test

Expected: nine new examples pass alongside the three completions specs.

### Step 7 — Wire expansion into `runCli`

Edit `nihongo-cli/src/Nihongo/Cli.hs`. Replace the body of `runCli`
with:

    runCli :: IO ()
    runCli = do
      rawArgs <- getArgs
      expanded <- expandRawArgs rawArgs
      cmd <-
        handleParseResult $
          execParserPure (prefs showHelpOnEmpty) parserInfo expanded
      runCommand cmd
      where
        parserInfo =
          info
            (commandParser <**> helper <**> versionInfoOption)
            ( fullDesc
                <> progDesc "Terminal-first Japanese learning companion."
                <> header "nihongo - kanji, vocabulary, readings, stroke order, and grammar from the command line."
            )

Add the new helper at the bottom of the module (it needs `IO`, `die`,
`getArgs`, `T.pack`, the alias map, and the loader):

    expandRawArgs :: [String] -> IO [String]
    expandRawArgs args = case args of
      [] -> pure args
      (first : _)
        | startsWithDash first -> pure args
        | T.pack first `elem` builtinCommands -> pure args
        | otherwise -> do
            cfgRes <- loadNihongoConfig
            case cfgRes of
              Left err -> die (renderConfigError err)
              Right cfg -> pure (expandAlias (resolveAliases cfg) args)
      where
        startsWithDash ('-' : _) = True
        startsWithDash _ = False

    renderConfigError :: ConfigError -> Text
    renderConfigError = \case
      ConfigFileReadError p msg ->
        "  failed to read " <> Text.pack p <> ": " <> msg
      ConfigParseError msg ->
        Text.unlines (map ("  " <>) (Text.lines msg))

    die :: Text -> IO a
    die msg = do
      TIO.hPutStrLn stderr ("nihongo: config error:\n" <> msg)
      exitWith (ExitFailure 1)

You will need new imports at the top of the file:

    import Nihongo.Cli.Aliases (builtinCommands, expandAlias)
    import Nihongo.Config.Load (loadNihongoConfig, resolveAliases)
    import Nihongo.Config.Types (ConfigError (..))
    import System.Environment (getArgs)
    import System.Exit (ExitCode (..), exitWith)
    import System.IO (stderr)

`Text` and `Text.IO` qualified imports are already present.

Run:

    cabal build all
    cabal run nihongo -- --version
    cabal run nihongo -- help

Expected: `--version` prints the version line; `help` lists topics. No
config errors because the helper bypasses the loader for built-in and
dash-prefixed first tokens.

Then exercise the alias path with a temp config:

    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/nihongo"
    cat > "$tmpdir/nihongo/config.kdl" <<'KDL'
    aliases {
      ks "kanji show"
    }
    KDL
    XDG_CONFIG_HOME="$tmpdir" cabal run nihongo -- ks 漢

Expected: identical output to `cabal run nihongo -- kanji show 漢`.

### Step 8 — Add `Nihongo.Cli.Alias` and the `alias` subcommand

Create `nihongo-cli/src/Nihongo/Cli/Alias.hs`:

    -- | The @nihongo alias@ subcommand surface.
    --
    -- Today this exposes only @nihongo alias list@ (also the default when
    -- no subcommand is supplied). The list view prints the resolved alias
    -- map as a sorted, padded @name = expansion@ table.
    module Nihongo.Cli.Alias
      ( AliasCommand (..),
        aliasCommandParser,
        handleAliasCommand,
        renderAliasTable,
      )
    where

    import Data.Map.Strict (Map)
    import Data.Map.Strict qualified as Map
    import Data.Text qualified as T
    import Data.Text.IO qualified as TIO
    import Nihongo.Config.Load (loadNihongoConfig, resolveAliases)
    import Nihongo.Config.Types (ConfigError (..))
    import Nihongo.Prelude
    import Options.Applicative
    import System.Exit (ExitCode (..), exitWith)
    import System.IO (stderr)

    data AliasCommand = AliasList
      deriving stock (Show, Eq)

    aliasCommandParser :: Parser AliasCommand
    aliasCommandParser =
      hsubparser
        ( command
            "list"
            ( info
                (pure AliasList <**> helper)
                (progDesc "List configured aliases")
            )
        )
        <|> pure AliasList

    handleAliasCommand :: AliasCommand -> IO ()
    handleAliasCommand AliasList = do
      result <- loadNihongoConfig
      case result of
        Left err -> do
          TIO.hPutStrLn stderr ("nihongo: config error:\n" <> renderError err)
          exitWith (ExitFailure 1)
        Right cfg -> TIO.putStr (renderAliasTable (resolveAliases cfg))

    renderError :: ConfigError -> Text
    renderError = \case
      ConfigFileReadError p msg ->
        "  failed to read " <> T.pack p <> ": " <> msg
      ConfigParseError msg ->
        T.unlines (map ("  " <>) (T.lines msg))

    -- | One line per entry, sorted ascending by alias name. Each name is
    -- padded to the longest name length so the @=@ separators align.
    -- Returns @"No aliases configured.\\n"@ for an empty map.
    renderAliasTable :: Map Text Text -> Text
    renderAliasTable m
      | Map.null m = "No aliases configured.\n"
      | otherwise =
          let entries = Map.toAscList m
              width = maximum (map (T.length . fst) entries)
           in T.unlines [pad width name <> " = " <> expansion | (name, expansion) <- entries]
      where
        pad w name = name <> T.replicate (w - T.length name) " "

In `nihongo-cli/src/Nihongo/Cli.hs`:

  * Add `import Nihongo.Cli.Alias qualified as Alias` near the other
    `Nihongo.Cli.*` imports.
  * Extend `Command` with `| CmdAlias !Alias.AliasCommand`.
  * Add a new `command "alias" …` block to `commandParser`:

        <> command
          "alias"
          ( info
              (CmdAlias <$> Alias.aliasCommandParser)
              (progDesc "Inspect configured command aliases")
          )

  * Add a `runCommand (CmdAlias c) = Alias.handleAliasCommand c` clause.
  * Export a new `runCliParserInfo :: ParserInfo Command` so tests can
    drive the parser without invoking IO. The simplest implementation is
    a top-level binding identical to the local `parserInfo` inside
    `runCli` (lifted out so both share it).

In `nihongo-cli/src/Nihongo/Cli/Aliases.hs`, update `builtinCommands`:

    builtinCommands :: [Text]
    builtinCommands =
      [ "hello",
        "help",
        "completions",
        "kanji",
        "alias"
      ]

### Step 9 — Help topic

Create `nihongo-cli/help/aliases.md`. Content (this is the verbatim
body the topic browser will display, so the prose is the user-facing
documentation):

    # Command Aliases

    nihongo can expand short aliases for longer command invocations
    before parsing. Aliases live in:

        $XDG_CONFIG_HOME/nihongo/config.kdl
        # macOS / Linux default: ~/.config/nihongo/config.kdl

    ## SCHEMA

    The file is in KDL (https://kdl.dev). Aliases live inside an
    `aliases { … }` block. Each child node's name is the alias key;
    its first quoted argument is the expansion:

        aliases {
          ks "kanji show"
          kp "kanji png"
          h  "help"
        }

    The expansion is split on whitespace, so it cannot contain
    arguments with embedded spaces. Use a shell alias for that case.

    ## EXPANSION RULES

    Only the first argument is matched. Trailing arguments are
    appended to the expansion. So with the example above:

        nihongo ks 漢   →   nihongo kanji show 漢

    Expansion is single-pass. If `a` expands to `b foo` and `b`
    expands to `c bar`, then `nihongo a x` becomes `nihongo b foo x`,
    not `nihongo c bar foo x`.

    ## BUILT-IN PROTECTION

    Built-in command names (`hello`, `help`, `completions`, `kanji`,
    `alias`) cannot be shadowed. An alias whose name is one of these
    is silently ignored at expansion time.

    Argv whose first token starts with `-` is also left alone, so
    `--version`, `--help`, and shell-completion entry paths
    (`--bash-completion-index …`) are never treated as aliases.

    ## PRECEDENCE

    Within one file, if the same alias name appears twice, the last
    occurrence wins.

    ## INSPECTING THE RESOLVED MAP

    Run `nihongo alias list` to print the resolved alias table:

        $ nihongo alias list
        h  = help
        kp = kanji png
        ks = kanji show

    The names are padded so the `=` separators align, and the entries
    are sorted ascending by alias name. If no config file exists, or
    the file contains no `aliases { … }` block, the output is:

        No aliases configured.

Register it in `nihongo-cli/src/Nihongo/Cli/Help.hs` by appending to
`helpTopics` (alphabetised):

    HelpTopic "aliases" "Configuring command aliases" $(embedStringFile "help/aliases.md"),

The `embedStringFile` template-haskell helper requires the path be
relative to the package root, which `help/aliases.md` already is.

### Step 10 — Extend the alias spec for the new surface

Update `nihongo-cli/test/Test/Nihongo/Cli/AliasesSpec.hs`. Append:

    import Data.List (find)
    import Nihongo.Cli (runCliParserInfo)
    import Nihongo.Cli.Alias (renderAliasTable)
    import Nihongo.Cli.Help (HelpTopic (..), helpTopics)
    import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure)
    import Data.Text qualified as T

    -- inside `spec`:
      describe "renderAliasTable" $ do
        it "prints a friendly note for an empty map" $
          renderAliasTable Map.empty `shouldBe` "No aliases configured.\n"

        it "renders a single entry without padding" $
          renderAliasTable (Map.singleton "ks" "kanji show")
            `shouldBe` "ks = kanji show\n"

        it "left-pads the longest name and aligns the '=' separators" $
          renderAliasTable
            ( Map.fromList
                [ ("h", "help"),
                  ("kp", "kanji png"),
                  ("ks", "kanji show")
                ]
            )
            `shouldBe` T.unlines
              [ "h  = help",
                "kp = kanji png",
                "ks = kanji show"
              ]

      describe "builtinCommands ↔ parser registry" $ do
        it "the parser accepts every name in builtinCommands" $
          mapM_
            ( \name ->
                case execParserPure defaultPrefs runCliParserInfo [T.unpack name, "--help"] of
                  Failure _ -> pure ()
                  Success _ -> expectationFailure (T.unpack name <> " --help unexpectedly succeeded")
                  CompletionInvoked _ -> expectationFailure (T.unpack name <> " --help triggered completion path")
            )
            builtinCommands

        it "the parser refuses an unknown top-level command" $
          case execParserPure defaultPrefs runCliParserInfo ["definitely-not-real"] of
            Failure _ -> pure ()
            _ -> expectationFailure "expected Failure for unknown subcommand"

      describe "nihongo help aliases" $ do
        it "is registered in the help topic index" $
          case find ((== "aliases") . (^. #topicName)) helpTopics of
            Nothing -> expectationFailure "aliases topic not registered"
            Just _ -> pure ()

        it "topic body covers schema, precedence, built-in protection, and listing" $
          case find ((== "aliases") . (^. #topicName)) helpTopics of
            Nothing -> expectationFailure "aliases topic not registered"
            Just t -> do
              ("SCHEMA" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True
              ("PRECEDENCE" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True
              ("BUILT-IN PROTECTION" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True
              ("nihongo alias list" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True

(The `(^. #topicName)` syntax uses generic-lens' `OverloadedLabels`,
which is already enabled project-wide via the `default-extensions` in
`common-options`. mina's test uses `.name` overloaded record-dot syntax;
nihongo prefers the lens spelling for consistency with the rest of
`Nihongo.Cli.Help`.)

Run:

    cabal build all
    cabal test all

Expected: every example green.


## Validation and Acceptance

End-to-end smoke test (Milestone 5). Run **after** `cabal install
nihongo` (or `nix build .` and use `result/bin/nihongo`):

    # 1. Set up a fresh config dir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/nihongo"
    cat > "$tmpdir/nihongo/config.kdl" <<'KDL'
    aliases {
      ks "kanji show"
      kp "kanji png"
      h  "help"
    }
    KDL

    # 2. With XDG_CONFIG_HOME pointed at it:
    export XDG_CONFIG_HOME="$tmpdir"

    # Inspection
    nihongo alias list
    # Expected:
    #   h  = help
    #   kp = kanji png
    #   ks = kanji show

    # Help topic
    nihongo help aliases
    # Expected: prints help/aliases.md verbatim

    # Aliased command (compare against the long form)
    diff <(nihongo ks 漢) <(nihongo kanji show 漢)
    # Expected: no output (identical)

    diff <(nihongo kp 漢) <(nihongo kanji png 漢)
    # Expected: no output

    nihongo h kanji-show
    # Expected: same body as `nihongo help kanji-show`

    # Built-in protection: alias an alias key that shadows a built-in
    cat > "$tmpdir/nihongo/config.kdl" <<'KDL'
    aliases {
      kanji "help"
    }
    KDL
    nihongo kanji show 漢
    # Expected: still runs `kanji show 漢`, NOT `help show 漢`.

    # Dash bypass: a broken file must not prevent --version
    cat > "$tmpdir/nihongo/config.kdl" <<'KDL'
    this is not valid kdl {
    KDL
    nihongo --version
    # Expected: prints version line, exit 0.

    # But explicit alias use surfaces the error
    nihongo someAlias 2>&1 | head -3
    # Expected:
    #   nihongo: config error:
    #     <kdl-hs decode error>
    #   …
    echo $?  # via PIPESTATUS[0] in zsh; expect non-zero

    # No file at all — must be silent
    rm "$tmpdir/nihongo/config.kdl"
    nihongo alias list
    # Expected: "No aliases configured."
    nihongo --version
    # Expected: prints version line.

If any of these diverge from "Expected", record the divergence in
**Surprises & Discoveries** with a transcript, then either adjust the
implementation or amend this section with the explanation.

Test commands (run from repo root):

    cabal test all
    # Expected:
    #   nihongo-core-tests:  N examples, 0 failures
    #   nihongo-cli-test:    M examples, 0 failures


## Idempotence and Recovery

All milestones are additive — they add new files, append to existing
data lists, and replace one function body (`runCli`). Any milestone can
be reverted by `git checkout` of the affected files. The Nix overlay
change in Milestone 1 is the only step that will trigger a network
fetch (the Hackage tarball); the SHA-256 in the overlay pins it.

If `cabal build` complains about a `kdl-hs` version solver conflict,
rerun with `-w ghc9122` and re-check that the dev shell is the one
provided by the flake (sometimes a stray system `ghc` is on PATH). The
`(nix:default)` indicator in the prompt confirms the right shell is
active. If the `nix/haskell-overlay.nix` `sha256` becomes stale (Hackage
revisions are immutable for the tarball but the URL could change in
theory), retrieve the new hash with:

    nix-prefetch-url --type sha256 \
      https://hackage.haskell.org/package/kdl-hs-1.0.1/kdl-hs-1.0.1.tar.gz

The smoke-test script writes only into a temporary directory under
`mktemp -d` and never touches `~/.config/nihongo/`. Cleanup is
automatic on shell exit.

Every commit on this plan must include both git trailers (per the
exec-plan skill's protocol):

    ExecPlan: docs/plans/11-add-user-defined-command-aliases-via-kdl-config.md
    Intention: intention_01kr04q2ajep5swkyba0vdjmyb


## Interfaces and Dependencies

### New libraries

  * `kdl-hs ^>=1.0` (Hackage) — KDL parser and decoder. Pulled into the
    Nix overlay via `callCabal2nix` from a Hackage tarball; pinned to
    1.0.1 to match what mina and notion-cli use today.

### New `nihongo-core` modules

  * `Nihongo.Config.Types` — exports `NihongoConfig (..)`,
    `AliasesSection (..)`, `ConfigError (..)`. Pure data; no IO.
  * `Nihongo.Config.Load` — exports
    `nihongoConfigDecoder :: KDL.DocumentDecoder NihongoConfig`,
    `decodeNihongoConfig :: Text -> Either ConfigError NihongoConfig`,
    `loadNihongoConfig :: IO (Either ConfigError NihongoConfig)`,
    `resolveAliases :: NihongoConfig -> Map Text Text`,
    `configFilePath :: IO FilePath`.
    Defines `instance KDL.DecodeNode AliasesSection`.

### New `nihongo-cli` modules

  * `Nihongo.Cli.Aliases` — exports
    `builtinCommands :: [Text]` and
    `expandAlias :: Map Text Text -> [String] -> [String]`. Pure.
  * `Nihongo.Cli.Alias` — exports `AliasCommand (..)`,
    `aliasCommandParser :: Parser AliasCommand`,
    `handleAliasCommand :: AliasCommand -> IO ()`,
    `renderAliasTable :: Map Text Text -> Text`.

### Changed `nihongo-cli` exports

  * `Nihongo.Cli` gains a `runCliParserInfo :: ParserInfo Command`
    export so tests can drive the parser via `execParserPure` without
    running `runCli`. The existing `runCli :: IO ()` keeps the same
    signature; only its body changes.
  * `Nihongo.Cli.Help.helpTopics` gains one element for the new
    `aliases` topic.

### New test modules

  * `nihongo-core/test/Test/Nihongo/Config/LoadSpec.hs` (registered in
    `nihongo-core/test/Main.hs`).
  * `nihongo-cli/test/Test/Nihongo/Cli/AliasesSpec.hs` (registered in
    `nihongo-cli/test/Main.hs`).

### Build system files

  * `nihongo-core/nihongo-core.cabal` — `kdl-hs ^>=1.0` added to the
    library `build-depends`; two new modules under `exposed-modules`;
    the new spec under the test-suite `other-modules`.
  * `nihongo-cli/nihongo-cli.cabal` — two new modules under
    `exposed-modules`; one new module under the test-suite
    `other-modules`. No new top-level `build-depends` (everything used
    by the new code — `text`, `containers`, `directory`, `filepath`,
    `optparse-applicative`, `nihongo-core` — is already listed).
  * `nix/haskell-overlay.nix` — adds the `kdl-hs` callCabal2nix
    override.
