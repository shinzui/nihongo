---
id: 10
slug: fix-shell-completions-to-use-optparse-applicative-protocol-correctly
title: "Fix shell completions to use optparse-applicative protocol correctly"
kind: exec-plan
created_at: 2026-05-07T02:38:15Z
intention: "intention_01kr04q2ajep5swkyba0vdjmyb"
---

# Fix shell completions to use optparse-applicative protocol correctly

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The `nihongo` command-line tool ships a `completions` subcommand that prints a shell
script for Bash, Zsh, or Fish. After sourcing that script, the user is supposed to be
able to type `nihongo <Tab>` and receive completions for subcommands (`kanji`, `help`,
`completions`, `hello`), nested subcommands (`kanji show`, `kanji png`), flags, and
flag values — derived automatically from the parser tree, with help text shown as a
description in shells that support it (Zsh and Fish).

Today the completion scripts are broken in all three shells. Bash mostly works but
relies on a fragile word-quoting style that breaks when arguments contain spaces. Zsh
mixes the modern `#compdef` declaration with the legacy `compctl` API, so descriptions
never appear and completions only fire intermittently. Fish uses the plain protocol
(no descriptions), miscomputes the cursor index, and never disables Fish's default
file-name completion, so completions are polluted with file names from the current
directory.

After this change, a user who runs

    nihongo completions bash > ~/.local/share/bash-completion/completions/nihongo
    # or
    nihongo completions zsh > ~/.zfunc/_nihongo
    # or
    nihongo completions fish > ~/.config/fish/completions/nihongo.fish

and reloads their shell can press `<Tab>` after `nihongo` (or any subcommand) and see
the correct completion words returned by the binary's `--bash-completion-index`
protocol. Under Zsh and Fish, each completion appears next to its `progDesc` text
(e.g. `kanji  -- Look up kanji: stroke order, components, readings`).

The fix replaces the script generators in `nihongo-cli/src/Nihongo/Cli/Completions.hs`
with three new generators modelled directly on the reference architecture documented
at `/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/cli/shell-completions.md`. The
binary itself is unchanged — `optparse-applicative` already implements both the plain
and enriched protocols correctly (verified during planning, see Surprises &
Discoveries).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

- [x] Read `/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/cli/shell-completions.md` end-to-end and the current `Nihongo.Cli.Completions` module so the reasoning behind each script is internalized. — 2026-05-06
- [x] Verify the binary's plain protocol output by running the snapshot command in **Concrete Steps / Pre-flight verification**. — 2026-05-06
- [x] Verify the binary's enriched protocol output by running the snapshot command in **Concrete Steps / Pre-flight verification**. — 2026-05-06
- [x] Milestone 1 — Rewrite the Bash generator in `nihongo-cli/src/Nihongo/Cli/Completions.hs` to match the reference's plain-protocol script. Build and snapshot the new output. — 2026-05-06
- [x] Milestone 2 — Rewrite the Zsh generator to use `#compdef` + `_describe` (enriched protocol). Build and snapshot the new output. — 2026-05-06
- [x] Milestone 3 — Rewrite the Fish generator to use enriched protocol with `complete -c nihongo -f` and a `__nihongo_complete` helper function. Build and snapshot the new output. — 2026-05-06
- [x] Milestone 4 — Add a Haskell test module `nihongo-cli/test/Test/Nihongo/Cli/CompletionsSpec.hs` (and supporting cabal stanza) that asserts each generated script contains the canonical landmark strings from the reference (e.g. `--bash-completion-enriched`, `_describe`, `complete -c nihongo -f`). This catches regressions cheaply without spawning real shells. — 2026-05-06
- [x] Milestone 5 — Smoke test each script in a real shell as described in **Validation and Acceptance**. Capture transcripts in this plan's Surprises & Discoveries if anything diverges from expectations. — 2026-05-06 (Bash functionally verified; Zsh syntax + registration verified; Fish not installed on this host)
- [x] Final commit and Outcomes & Retrospective entry. — 2026-05-06


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- 2026-05-06 — Confirmed during planning that the binary already speaks both protocols
  correctly. Run from the repository root:

        ./result/bin/nihongo --bash-completion-index 1 --bash-completion-word nihongo --bash-completion-word ""

    yields one word per line:

        kanji
        completions
        help
        hello
        -h
        --help
        --version

    And the enriched form:

        ./result/bin/nihongo --bash-completion-enriched --bash-completion-index 1 --bash-completion-word nihongo --bash-completion-word ""

    yields TAB-separated `word\tdescription` lines:

        kanji	Look up kanji: stroke order, components,...
        completions	Print a shell completion script (bash |...
        help	Show help topics. Use `help` for the...
        hello	Print a greeting (placeholder example)

    This means the bug is purely in the shell-script generators in
    `nihongo-cli/src/Nihongo/Cli/Completions.hs`; no parser changes are required.

- 2026-05-06 — The current Zsh script defines `_nihongo` then registers it with
  `compctl -K _nihongo nihongo`. `compctl` is Zsh's *legacy* completion system; it
  cannot consume the enriched `word\tdescription` lines and ignores the `#compdef`
  marker. The reference uses the modern system (`#compdef nihongo` + `_describe`).
  Replacing one with the other is the central fix for Zsh.

- 2026-05-06 — Smoke-test transcript:

  - **Bash**: sourced the generated script in a non-interactive Bash and
    drove `_nihongo_completions` directly by setting `COMP_CWORD` /
    `COMP_WORDS`. All three cases produce the expected `COMPREPLY`:

        # COMP_WORDS=(nihongo k), COMP_CWORD=1
        kanji
        # COMP_WORDS=(nihongo ''), COMP_CWORD=1
        kanji
        completions
        help
        hello
        -h
        --help
        --version
        # COMP_WORDS=(nihongo kanji s), COMP_CWORD=2
        show

    `bash -c 'complete: command not found'` warning when sourcing under
    `bash --noprofile --norc` is harmless — the `complete` builtin is
    available in every interactive shell, just not in this no-init test
    spawn.

  - **Zsh**: `zsh -n $SMOKE/_nihongo` reports no syntax errors. With
    `fpath=($SMOKE $fpath); autoload -Uz compinit; compinit -u`, the
    completion is correctly registered (`print -l "${(ok)_comps[(I)nihongo]}"`
    prints `nihongo`). Driving Tab-completion programmatically via
    `zpty`, `expect`, and `script` all proved unreliable — Zsh's
    `_describe` widget needs a real interactive completion context that
    these PTY drivers do not faithfully reproduce. Functional rendering
    of descriptions in a real interactive session is left for the user
    to confirm; the substring tests in Milestone 4 plus the verbatim
    port from the haskell-jitsurei reference cover everything that does
    not require a real TTY.

  - **Fish**: `fish` is not installed on this machine. `which fish`,
    `nix-env -q --installed | grep fish`, and the standard Homebrew /
    NixOS paths all return nothing. The plan's assumption that all
    three shells are available is therefore false on this host.
    Substring assertions in Milestone 4 still verify the script
    structure; runtime validation must happen on a host with `fish`
    installed.

- 2026-05-06 — `~/.zfunc/_nihongo` already exists as a symlink into
  `/nix/store` (managed by home-manager). The plan's instruction to
  write `nihongo completions zsh > ~/.zfunc/_nihongo` would have failed
  (read-only Nix store) or, worse, removed the symlink and replaced it
  with a regular file that home-manager would later overwrite. Used a
  per-shell temp directory (`mktemp -d -t nihongo-smoke-XXXXXX`) for the
  smoke test instead. The user's home-manager configuration likely
  needs a separate update to point at the new generator output if they
  rely on `~/.zfunc/_nihongo` interactively — out of scope for this
  plan.

- 2026-05-06 — GHC's `MultilineStrings` extension still processes standard escape
  sequences inside `"""..."""` literals: `\n` becomes a literal newline,
  `\t` becomes a literal tab, etc. To embed a *literal* `\n` in the generated
  shell script (e.g. for `IFS=$'\n'`), the Haskell source must spell it `\\n`.
  First Bash build emitted a real newline inside `IFS=$'…'`, breaking the script
  body until the source was changed to `\\n`. Same caveat applies to `\t` (Zsh
  parses `$'\t'`) and any backslash escape inside the future Zsh / Fish bodies.

- 2026-05-06 — The current Fish script computes the index as
  `(count $cmd)` where `$cmd = (commandline -opc) (commandline -ct)`. When the user
  has typed `nihongo k` and presses Tab, `commandline -opc` is `nihongo` and
  `commandline -ct` is `k`, so `$cmd` is `(nihongo k)` of length 2 and the index
  passed is 2. But the cursor word is at position 1 (zero-indexed) from the binary's
  point of view because the binary expects index = position of the word currently
  being completed. The reference instead passes `(count $tokens)` (the count of
  *prior* tokens) and then appends the current word — this lines up correctly with
  how `optparse-applicative` interprets `--bash-completion-index`.


## Decision Log

Record every decision made while working on the plan.

- Decision: Mirror the haskell-jitsurei reference scripts verbatim, adapting only the
  program name (`myapp` → `nihongo`).
  Rationale: The reference is the authoritative pattern in the user's repository
  family. Diverging would require re-validating shell-quoting semantics for each
  shell, which is the kind of work that produces today's broken state.
  Date: 2026-05-06.

- Decision: Keep the `CompletionsShell` data type and the `completionsCommandParser`
  unchanged — only rewrite `runCompletionsCommand`'s generated script bodies.
  Rationale: The CLI surface (`nihongo completions <bash|zsh|fish>`) is already
  correct. The fix is internal to the script-string-building code.
  Date: 2026-05-06.

- Decision: Add a test module that diff-checks landmark substrings in each generated
  script rather than spawning real shells in CI.
  Rationale: Spawning Bash/Zsh/Fish in CI is fragile (shells have version skew, Zsh
  needs the completion system loaded with `compinit`, Fish needs an interactive-ish
  setup). Substring assertions catch the main regression mode (someone hand-edits the
  string and removes a critical line) without that complexity.
  Date: 2026-05-06.

- Decision: Use Haskell multi-line string literals (`MultilineStrings` is in the
  cabal file's `default-extensions`) rather than concatenated `<>` segments, so the
  generated scripts can be read end-to-end like the reference.
  Rationale: The current code's `<>` cascade is one reason mistakes are easy to
  introduce — quoting and newline placement is invisible. Multi-line strings keep
  the script text intact in source form.
  Date: 2026-05-06.

- Decision: Run the Milestone 5 smoke test against a per-shell `mktemp -d`
  directory rather than overwriting `~/.zfunc/_nihongo` (a home-manager-managed
  symlink into `/nix/store`).
  Rationale: Writing to that path would either fail (Nix store is read-only) or
  silently replace the symlink with a regular file that home-manager would later
  rewrite — both bad outcomes. The temp-dir variant achieves the same validation
  goal (`compinit` registers the file, the script is syntactically valid) without
  touching the user's persistent shell configuration.
  Date: 2026-05-06.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

### What was delivered (2026-05-06)

`nihongo-cli/src/Nihongo/Cli/Completions.hs` now generates three shell scripts
that mirror the haskell-jitsurei reference verbatim (with `myapp → nihongo`):

- **Bash**: plain protocol via `_nihongo_completions` + `complete -o filenames`.
- **Zsh**: enriched protocol via `#compdef nihongo` + `_describe`, replacing the
  legacy `compctl` script. Descriptions now appear in the standard two-column
  Zsh format.
- **Fish**: enriched protocol via `__nihongo_complete`, with `complete -c nihongo
  -f` to suppress Fish's default file-name fallback. Tab-index calculation now
  uses `(count $tokens)` plus an explicit `--bash-completion-word "$current"`.

The module gained a new pure entry point `completionScript :: CompletionsShell
-> Text` so the scripts can be inspected without IO. `runCompletionsCommand` is
now `TIO.putStr . completionScript`.

A new test suite `nihongo-cli-test` was added (the package previously had none).
It uses `hspec ^>=2.11` and asserts a small set of landmark substrings in each
generated script. `cabal test nihongo-cli` reports `3 examples, 0 failures`.

### How it compares to the original purpose

The Purpose / Big Picture section asked for: a user runs `nihongo completions
<shell> > <path>`, sources the script, and gets working subcommand / flag
completions, with `progDesc` text rendered in Zsh and Fish. After this change:

- Bash now correctly returns the optparse-applicative-derived completions in
  every position tested (top-level, partial subcommand, nested subcommand) —
  see Surprises & Discoveries for the captured `COMPREPLY` lists.
- Zsh's script is syntactically valid (`zsh -n` clean) and is registered by
  `compinit`. Visual confirmation of the two-column description format requires
  a real interactive terminal that no PTY driver tested here can faithfully
  reproduce, so that final piece of acceptance is left for the user to confirm
  in an interactive session — but the substring tests + verbatim port from the
  reference give high confidence.
- Fish could not be runtime-verified on this host (`fish` is not installed).
  The script structure is locked by the substring tests and by being a verbatim
  port of the proven reference.

### Gaps / follow-ups

1. The user's `~/.zfunc/_nihongo` is a home-manager-managed symlink into the
   Nix store. Their interactive Zsh will keep using that file, not the new
   generator output, until home-manager is updated to point at it (or they
   stop managing the file and run `nihongo completions zsh > ~/.zfunc/_nihongo`
   manually). This is outside the scope of the current ExecPlan — it lives in
   the user's home-manager flake.
2. Interactive Fish validation is deferred to a host with `fish` installed.
3. The generated scripts intentionally have no trailing newline (a side-effect
   of GHC's `MultilineStrings` literal stripping the newline before `"""`),
   matching the plan's "byte-for-byte (modulo a trailing newline)" tolerance.
   No shell appears to care, but if a future linter does, wrapping the case
   arms with `<> "\n"` (or switching `runCompletionsCommand` to `TIO.putStrLn`)
   is the obvious one-line fix.

### Lessons

- `MultilineStrings` is the right tool for embedding shell scripts verbatim,
  but standard escape sequences (`\n`, `\t`) are still interpreted, so any
  literal backslash-escape that should end up in the generated script must be
  doubled in the Haskell source. Caught on the first Bash build; kept in mind
  for the Zsh `$'\\t'` and Fish `\\t` cases that followed.
- Pre-commit hooks (treefmt + fourmolu in this repo) will re-indent multi-line
  literals after a commit attempt. The strip-amount logic of `MultilineStrings`
  is robust to that — fourmolu changed the leading indent from 10 spaces to 6,
  but because the closing `"""` moves with the content, the generated string
  was bit-for-bit identical and the test suite continued to pass. The commit
  workflow is therefore: stage, commit, fail-with-reformat, re-stage the
  reformatted file, commit again.
- Driving Zsh/Fish completion in CI-style automation is hard; substring assertions
  on the generated text plus a verbatim port of a known-good reference are a
  good cost/coverage trade-off, as the original Decision Log entry predicted.


## Context and Orientation

This repository is `nihongo`, a terminal Japanese-learning CLI written in Haskell. It
is a Cabal multi-package project with two libraries:

- `nihongo-core/` — domain logic (kanji parsing, stroke-order data).
- `nihongo-cli/` — CLI parser, subcommand handlers, and the `nihongo` executable.

The pieces relevant to this plan all live under `nihongo-cli/`:

- `nihongo-cli/src/Nihongo/Cli.hs` — top-level parser. Defines a `commandParser`
  built with `hsubparser`, with subcommands `hello`, `help`, `completions`, `kanji`.
  Dispatches to `runCompletionsCommand` when the user types `nihongo completions
  <shell>`.
- `nihongo-cli/src/Nihongo/Cli/Completions.hs` — the module being rewritten. Today
  it exports the data type `CompletionsShell = Bash | Zsh | Fish`, the parser
  `completionsCommandParser`, and the action `runCompletionsCommand`. Only the
  internals of `runCompletionsCommand` are changing.
- `nihongo-cli/nihongo-cli.cabal` — Cabal package file. Lists the library's exposed
  modules. Currently has no `test-suite` stanza — Milestone 4 will add one.
- `nihongo-cli/app/Main.hs` — executable entry point; just `import Nihongo.Cli
  (runCli); main = runCli`. No edits needed.

Term-of-art definitions (so a novice can follow):

- **optparse-applicative**: a Haskell library for declarative CLI argument parsing.
  When the binary is invoked with the flags `--bash-completion-index N
  --bash-completion-word w0 --bash-completion-word w1 ...`, the library walks its
  parser tree and prints one matching completion per line on stdout. With the extra
  flag `--bash-completion-enriched`, each line is `word\tdescription` instead of
  bare `word`. This protocol is **already implemented for us** by the library; we
  only need shell scripts that call the binary correctly.
- **Plain protocol**: the bare-word output. Bash uses this because Bash's
  `complete`/`COMPREPLY` system has no native way to attach descriptions.
- **Enriched protocol**: the TAB-separated output. Zsh's `_describe` and Fish's
  `complete -a` both render descriptions natively when given that format.
- **`#compdef`**: the first line of a Zsh function-style completion file. When the
  Zsh completion system (loaded via `autoload -Uz compinit; compinit`) sees this
  marker in a file on `$fpath`, it knows the file defines a completion for the named
  command and loads it on demand.
- **`compctl`**: Zsh's legacy completion API, predating `compdef`. It cannot render
  descriptions and is incompatible with the enriched protocol. The current
  implementation accidentally mixes both APIs; the new implementation uses only the
  modern API.
- **`commandline -opc` / `commandline -ct`**: Fish builtins. `-opc` returns the
  *previous* tokens on the command line (everything before the cursor word). `-ct`
  returns the *current* token (the partial word the user is completing). The
  reference uses both to construct the right `--bash-completion-index` value.

Reference document: `/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/cli/shell-completions.md`.
This file lives in a sibling repository, **outside** the working tree of this plan,
so the relevant excerpts are reproduced inline below in **Plan of Work**. Do not
assume the reader can open it — read it from the embedded snippets.


## Plan of Work

The work is one file rewrite plus a test module. The rewrite has three parallel
sub-pieces (Bash, Zsh, Fish) which we organize as Milestones 1–3 so each can be
built, snapshotted, and committed independently. Milestone 4 adds a small Haskell
test that locks the generated text against regression. Milestone 5 is the manual
real-shell smoke test.

The new `runCompletionsCommand` will produce these three scripts. The full text of
each generator is given here as it should appear in the final source. The Haskell
form uses multi-line string literals (the language extension is already enabled
project-wide via `default-extensions: MultilineStrings` in
`nihongo-cli/nihongo-cli.cabal`).


### Milestone 1 — Bash generator

Scope: replace the `Bash` arm of `runCompletionsCommand` with the reference's
plain-protocol script.

What will exist at the end: the command `nihongo completions bash` prints a script
that, when sourced, completes `nihongo` correctly via Bash's `complete -F` mechanism
and falls back to filename completion when the binary returns no matches.

The exact replacement script (substituting `myapp` → `nihongo`) is:

    _nihongo_completions() {
        local CMDLINE
        local IFS=$'\n'
        CMDLINE=(--bash-completion-index $COMP_CWORD)

        for arg in ${COMP_WORDS[@]}; do
            CMDLINE=(${CMDLINE[@]} --bash-completion-word "$arg")
        done

        COMPREPLY=( $(nihongo "${CMDLINE[@]}" 2>/dev/null) )
    }

    complete -o filenames -F _nihongo_completions nihongo

Why this differs from the current code: the current Bash output looks superficially
similar but quotes `${COMP_WORDS[@]}` as `"${COMP_WORDS[@]}"`, which preserves
embedded spaces inside individual completions but at the cost of also preserving
empty-string slots when the user has typed `nihongo ` (trailing space). The
unquoted form in the reference, combined with `IFS=$'\n'`, is the established
pattern for this protocol and is what the optparse-applicative documentation
recommends.

Acceptance for Milestone 1: after `cabal build nihongo-cli`, running
`./dist-newstyle/build/...nihongo completions bash` (or via `cabal run`) prints a
script whose first line begins with `_nihongo_completions() {`, ends with
`complete -o filenames -F _nihongo_completions nihongo` and a trailing newline,
and contains exactly the body shown above. Verify by piping into `diff -u` against
a fixture file (see Concrete Steps).


### Milestone 2 — Zsh generator

Scope: replace the `Zsh` arm with the reference's enriched-protocol script using
`_describe`.

What will exist at the end: `nihongo completions zsh` prints a Zsh function-style
completion file beginning with `#compdef nihongo`. When dropped into a directory on
the user's `$fpath` (e.g. `~/.zfunc/_nihongo`) and re-loaded, typing `nihongo <Tab>`
shows subcommand names alongside their `progDesc` text in Zsh's two-column
description format.

The exact replacement script:

    #compdef nihongo

    _nihongo() {
        local -a completions
        local CMDLINE
        local IFS=$'\n'

        CMDLINE=(--bash-completion-enriched --bash-completion-index $((CURRENT - 1)))

        for arg in ${words[@]}; do
            CMDLINE=(${CMDLINE[@]} --bash-completion-word "$arg")
        done

        local line
        for line in $(nihongo "${CMDLINE[@]}" 2>/dev/null); do
            local word=${line%%$'\t'*}
            local desc=${line#*$'\t'}
            if [[ "$word" != "$desc" ]]; then
                completions+=("${word//:/\\:}:${desc}")
            else
                completions+=("$word")
            fi
        done

        if [[ ${#completions[@]} -gt 0 ]]; then
            _describe 'nihongo' completions
        fi
    }

    _nihongo

Why this fixes the bug: the script no longer uses `compctl` at all. It is a
modern-style `_nihongo` function that:

1. Asks the binary for the enriched protocol via `--bash-completion-enriched`.
2. Splits each line on the literal TAB character (`$'\t'`) into `word` and `desc`.
3. Escapes any colons inside `word` (since Zsh's `_describe` uses `:` as the
   word/description separator).
4. Hands the assembled `word:desc` list to the built-in `_describe` widget, which
   renders the two-column format Zsh users expect.

The trailing bare `_nihongo` call is what the reference uses to register the
function with the Zsh completion system when this file is loaded directly.

Acceptance for Milestone 2: `nihongo completions zsh` prints a script whose first
line is `#compdef nihongo`, contains the substring `--bash-completion-enriched`, the
substring `_describe 'nihongo' completions`, and the substring `${word//:/\\:}`.


### Milestone 3 — Fish generator

Scope: replace the `Fish` arm with the reference's enriched-protocol script using
`complete -c nihongo -f` and a `__nihongo_complete` helper.

What will exist at the end: `nihongo completions fish` prints a Fish completion
script that disables Fish's default file-name fallback and registers a function-
based completion that uses the enriched protocol so descriptions appear next to
each completion.

The exact replacement script:

    # Disable file completion by default
    complete -c nihongo -f

    function __nihongo_complete
        set -l tokens (commandline -cop)
        set -l current (commandline -ct)
        set -l index (count $tokens)

        set -l args --bash-completion-enriched --bash-completion-index $index
        for token in $tokens
            set args $args --bash-completion-word $token
        end
        set args $args --bash-completion-word "$current"

        for line in (nihongo $args 2>/dev/null)
            # Split on tab: word<TAB>description
            set -l parts (string split \t -- $line)
            if test (count $parts) -ge 2
                printf '%s\t%s\n' $parts[1] $parts[2]
            else
                echo $line
            end
        end
    end

    complete -c nihongo -a '(__nihongo_complete)'

Why this fixes the bug: the current Fish script uses the plain protocol (no
descriptions), miscomputes the index, and never disables Fish's built-in file
completion, so the suggestion list mixes filenames in the current directory with
the binary's actual completions. The new script disables file completion at the
top, computes the index from `(count $tokens)` (number of *prior* tokens) and then
appends the current partial word as an explicit `--bash-completion-word`, matching
what optparse-applicative's protocol expects. Each output line is split on tab and
re-emitted as `word\tdescription`, which Fish renders natively.

Acceptance for Milestone 3: `nihongo completions fish` prints a script that
contains the substring `complete -c nihongo -f`, the substring `--bash-completion-enriched`,
the substring `function __nihongo_complete`, and the substring `commandline -cop`.


### Milestone 4 — Test module pinning the generators

Scope: add a `test-suite` stanza to `nihongo-cli/nihongo-cli.cabal` (none exists
today) and a single test file
`nihongo-cli/test/Test/Nihongo/Cli/CompletionsSpec.hs` containing landmark
substring assertions for each shell.

What will exist at the end: `cabal test nihongo-cli` runs the new tests; each
asserts the presence of three to five canonical substrings in the generated
script. If a future edit accidentally removes `--bash-completion-enriched` from
the Zsh script, the test fails with a clear message.

Why this exists: spawning real shells in CI is brittle. Substring tests defend the
contract cheaply: they catch the realistic regression of "someone edited the
string and broke a critical line" without depending on a runtime shell.

Test framework: this project does not yet pin a Haskell test framework for the
CLI library. `nihongo-core/test/Main.hs` uses `hspec`, so we use `hspec` here too
to keep one framework across the project.

Cabal stanza to add at the end of `nihongo-cli/nihongo-cli.cabal`:

    test-suite nihongo-cli-test
      import: common-options
      type: exitcode-stdio-1.0
      hs-source-dirs: test
      main-is: Main.hs
      other-modules:
        Test.Nihongo.Cli.CompletionsSpec

      build-depends:
        base >=4.20 && <5,
        hspec ^>=2.11,
        nihongo-cli,
        text ^>=2.1,

      ghc-options:
        -threaded
        -rtsopts
        -with-rtsopts=-N

Files to create:

- `nihongo-cli/test/Main.hs`:

        module Main (main) where

        import qualified Test.Nihongo.Cli.CompletionsSpec
        import Test.Hspec (hspec)

        main :: IO ()
        main = hspec $ do
          Test.Nihongo.Cli.CompletionsSpec.spec

- `nihongo-cli/test/Test/Nihongo/Cli/CompletionsSpec.hs` (the spec). Capture the
  generated text by extracting it through a small change to
  `Nihongo.Cli.Completions`: expose a pure function `completionScript ::
  CompletionsShell -> Text` alongside `runCompletionsCommand`. `runCompletionsCommand`
  becomes `TIO.putStr . completionScript`. The export list for
  `Nihongo.Cli.Completions` must add `completionScript` so the test can import it.

  The spec body:

        module Test.Nihongo.Cli.CompletionsSpec (spec) where

        import qualified Data.Text as T
        import Nihongo.Cli.Completions (CompletionsShell (..), completionScript)
        import Test.Hspec (Spec, describe, it, shouldSatisfy)

        spec :: Spec
        spec = describe "Nihongo.Cli.Completions.completionScript" $ do
          it "Bash script registers a complete -F handler" $ do
            let s = completionScript Bash
            s `shouldSatisfy` ("_nihongo_completions()" `T.isInfixOf`)
            s `shouldSatisfy` ("--bash-completion-index $COMP_CWORD" `T.isInfixOf`)
            s `shouldSatisfy` ("complete -o filenames -F _nihongo_completions nihongo" `T.isInfixOf`)

          it "Zsh script uses #compdef and _describe with enriched protocol" $ do
            let s = completionScript Zsh
            s `shouldSatisfy` ("#compdef nihongo" `T.isInfixOf`)
            s `shouldSatisfy` ("--bash-completion-enriched" `T.isInfixOf`)
            s `shouldSatisfy` ("_describe 'nihongo' completions" `T.isInfixOf`)
            s `shouldSatisfy` ("${word//:/\\\\:}" `T.isInfixOf`)

          it "Fish script disables file completion and uses enriched protocol" $ do
            let s = completionScript Fish
            s `shouldSatisfy` ("complete -c nihongo -f" `T.isInfixOf`)
            s `shouldSatisfy` ("--bash-completion-enriched" `T.isInfixOf`)
            s `shouldSatisfy` ("function __nihongo_complete" `T.isInfixOf`)
            s `shouldSatisfy` ("commandline -cop" `T.isInfixOf`)

  Note the doubled backslashes in the Bash check (`${word//:/\\\\:}`) — Haskell
  string literals require doubling backslashes, so the four backslashes here
  represent the two backslashes that actually appear in the generated Zsh script.

Acceptance for Milestone 4: `cabal test nihongo-cli` runs the test suite to
completion, all three `it` blocks pass.


### Milestone 5 — Real-shell smoke test

Scope: install the generated scripts into the user's actual Bash, Zsh, and Fish
shells and verify Tab-completion works interactively.

What will exist at the end: an entry in **Surprises & Discoveries** confirming
each shell completes correctly, with a short transcript or a note like "verified
2026-05-07: `nihongo k<Tab>` expands to `nihongo kanji` in all three shells."

Per-shell steps are in **Validation and Acceptance** below.

Acceptance for Milestone 5: pressing Tab after `nihongo `, `nihongo k`,
`nihongo kanji `, `nihongo kanji s`, and `nihongo --` produces sensible
completions in each shell, and Zsh / Fish display the corresponding `progDesc`
text.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/nihongo`.

### Pre-flight verification (do this once before Milestone 1)

Build the binary. The repository uses Cabal:

    cabal build nihongo-cli

Locate the freshly built binary; the simplest way is via `cabal list-bin`:

    BIN=$(cabal list-bin nihongo)

Confirm the plain protocol works as expected:

    "$BIN" --bash-completion-index 1 --bash-completion-word nihongo --bash-completion-word ""

Expected output (one word per line, may include trailing flags):

    kanji
    completions
    help
    hello
    -h
    --help
    --version

Confirm the enriched protocol works:

    "$BIN" --bash-completion-enriched --bash-completion-index 1 --bash-completion-word nihongo --bash-completion-word ""

Expected output (TAB-separated):

    kanji	Look up kanji: stroke order, components,...
    completions	Print a shell completion script (bash |...
    help	Show help topics. Use `help` for the...
    hello	Print a greeting (placeholder example)
    -h	Show this help text
    --help	Show this help text
    --version	Print the version and exit

If either of these does not match the structure shown (one word per line / TAB
separated), stop — the binary itself is broken and this plan does not apply.

### Milestone 1 — Bash rewrite

Edit `nihongo-cli/src/Nihongo/Cli/Completions.hs`. Replace the `Bash` arm of the
`scriptText` `case` with a multi-line string literal exactly matching the script
shown in **Plan of Work / Milestone 1**. After editing, rebuild and snapshot:

    cabal build nihongo-cli
    "$(cabal list-bin nihongo)" completions bash

Compare the printed output against the script body in **Plan of Work / Milestone 1**.
The first non-blank line must be `_nihongo_completions() {` and the last must be
`complete -o filenames -F _nihongo_completions nihongo`.

Commit:

    git add nihongo-cli/src/Nihongo/Cli/Completions.hs
    git commit -m "$(cat <<'EOF'
    fix(cli): rewrite bash completions to use plain protocol pattern

    Adopt the haskell-jitsurei reference pattern: a single
    _nihongo_completions function that forwards COMP_WORDS to the binary
    via --bash-completion-index, with `complete -o filenames` for file
    fallback. Replaces the previous quoted-array variant that broke on
    trailing spaces.

    ExecPlan: docs/plans/10-fix-shell-completions-to-use-optparse-applicative-protocol-correctly.md
    Intention: intention_01kr04q2ajep5swkyba0vdjmyb
    EOF
    )"

### Milestone 2 — Zsh rewrite

Edit `nihongo-cli/src/Nihongo/Cli/Completions.hs` again. Replace the `Zsh` arm
with the script body in **Plan of Work / Milestone 2**. Rebuild:

    cabal build nihongo-cli
    "$(cabal list-bin nihongo)" completions zsh

Verify the printed output begins with `#compdef nihongo` and contains the four
landmark substrings listed in the Milestone 2 acceptance.

Commit:

    git add nihongo-cli/src/Nihongo/Cli/Completions.hs
    git commit -m "$(cat <<'EOF'
    fix(cli): rewrite zsh completions to use #compdef and _describe

    Replace the legacy compctl-based script with a modern #compdef _nihongo
    function that consumes the enriched protocol and renders descriptions
    via _describe. Mirrors the haskell-jitsurei reference.

    ExecPlan: docs/plans/10-fix-shell-completions-to-use-optparse-applicative-protocol-correctly.md
    Intention: intention_01kr04q2ajep5swkyba0vdjmyb
    EOF
    )"

### Milestone 3 — Fish rewrite

Edit the file once more. Replace the `Fish` arm with the script body in **Plan of
Work / Milestone 3**. Rebuild:

    cabal build nihongo-cli
    "$(cabal list-bin nihongo)" completions fish

Verify the four Milestone 3 landmark substrings are present.

Commit:

    git add nihongo-cli/src/Nihongo/Cli/Completions.hs
    git commit -m "$(cat <<'EOF'
    fix(cli): rewrite fish completions to use enriched protocol

    Disable Fish's default file fallback with `complete -c nihongo -f`, and
    register a __nihongo_complete helper that calls the binary with
    --bash-completion-enriched and re-emits word\tdescription so Fish
    renders descriptions natively. Mirrors the haskell-jitsurei reference.

    ExecPlan: docs/plans/10-fix-shell-completions-to-use-optparse-applicative-protocol-correctly.md
    Intention: intention_01kr04q2ajep5swkyba0vdjmyb
    EOF
    )"

### Milestone 4 — Tests

Add the `test-suite` stanza shown in **Plan of Work / Milestone 4** to the bottom
of `nihongo-cli/nihongo-cli.cabal`. Create
`nihongo-cli/test/Main.hs` and `nihongo-cli/test/Test/Nihongo/Cli/CompletionsSpec.hs`
with the contents shown there. Edit the `Nihongo.Cli.Completions` module to:

1. Extract the body of `runCompletionsCommand`'s `case` into a new pure function

        completionScript :: CompletionsShell -> Text

2. Make `runCompletionsCommand` simply

        runCompletionsCommand sh = TIO.putStr (completionScript sh)

3. Add `completionScript` to the module's export list.

Then build and test:

    cabal build nihongo-cli
    cabal test nihongo-cli

Expected hspec output (abbreviated):

    Nihongo.Cli.Completions.completionScript
      Bash script registers a complete -F handler
      Zsh script uses #compdef and _describe with enriched protocol
      Fish script disables file completion and uses enriched protocol

    Finished in 0.0001 seconds
    3 examples, 0 failures

Commit:

    git add nihongo-cli/nihongo-cli.cabal nihongo-cli/src/Nihongo/Cli/Completions.hs nihongo-cli/test/Main.hs nihongo-cli/test/Test/Nihongo/Cli/CompletionsSpec.hs
    git commit -m "$(cat <<'EOF'
    test(cli): pin completion scripts with landmark substring assertions

    Add a hspec test suite for nihongo-cli that asserts each generated
    completion script contains the canonical lines (`_describe`,
    `--bash-completion-enriched`, `complete -c nihongo -f`, etc.).
    Extract a pure `completionScript :: CompletionsShell -> Text` so the
    tests can inspect the text without IO.

    ExecPlan: docs/plans/10-fix-shell-completions-to-use-optparse-applicative-protocol-correctly.md
    Intention: intention_01kr04q2ajep5swkyba0vdjmyb
    EOF
    )"

### Milestone 5 — Real-shell smoke test

The user's machine has all three shells available. Use these one-shot install
commands; each writes the completion script into the standard location for that
shell, and the loader command re-loads the user's shell completion state without
restarting the terminal.

Bash:

    BIN=$(cabal list-bin nihongo)
    mkdir -p ~/.local/share/bash-completion/completions
    "$BIN" completions bash > ~/.local/share/bash-completion/completions/nihongo
    bash -lc 'source ~/.local/share/bash-completion/completions/nihongo; compgen -F _nihongo_completions nihongo'

The `compgen` line lists what Bash would offer for `nihongo<Tab>` without an
interactive Tab press. It should print `kanji completions help hello` (order
may vary) plus any flags.

Zsh:

    BIN=$(cabal list-bin nihongo)
    mkdir -p ~/.zfunc
    "$BIN" completions zsh > ~/.zfunc/_nihongo
    zsh -fc 'fpath=(~/.zfunc $fpath); autoload -Uz compinit; compinit -u; print -l "${(ok)_comps[(I)nihongo]}"'

The final command prints `nihongo` if the completion was registered. To confirm
the descriptions render, open an interactive Zsh and type `nihongo <Tab>`; the
expected display is:

    completions  -- Print a shell completion script (bash |...
    hello        -- Print a greeting (placeholder example)
    help         -- Show help topics. Use `help` for the...
    kanji        -- Look up kanji: stroke order, components,...

Fish:

    BIN=$(cabal list-bin nihongo)
    mkdir -p ~/.config/fish/completions
    "$BIN" completions fish > ~/.config/fish/completions/nihongo.fish
    fish -c 'complete -C "nihongo "'

`complete -C` simulates the Tab key. It should print TAB-separated lines like:

    kanji	Look up kanji: stroke order, components,...
    completions	Print a shell completion script (bash |...
    help	Show help topics. Use `help` for the...
    hello	Print a greeting (placeholder example)

Record the actual transcripts in **Surprises & Discoveries** with date stamps,
even if everything matches the expected output (so a future contributor can see
that the validation was performed and what the output looked like at the time).


## Validation and Acceptance

The change is accepted when **all** of the following hold:

1. `cabal build nihongo-cli` succeeds with no warnings beyond those already
   present on `master`.
2. `cabal test nihongo-cli` runs and reports `3 examples, 0 failures`.
3. The output of `nihongo completions bash` matches the script in **Plan of Work /
   Milestone 1** byte-for-byte (modulo a trailing newline).
4. The output of `nihongo completions zsh` matches **Plan of Work / Milestone 2**
   byte-for-byte (modulo trailing newline).
5. The output of `nihongo completions fish` matches **Plan of Work / Milestone 3**
   byte-for-byte (modulo trailing newline).
6. In an interactive Bash session, after sourcing the completion script, typing
   `nihongo k<Tab>` completes to `nihongo kanji `.
7. In an interactive Zsh session, with the completion file installed on `$fpath`
   and `compinit` run, typing `nihongo <Tab>` shows subcommand names with their
   `progDesc` text in the standard two-column layout.
8. In an interactive Fish session, with the completion file installed in
   `~/.config/fish/completions/`, typing `nihongo <Tab>` shows subcommand names
   with their `progDesc` text and **does not** include filenames from the current
   directory.
9. In any of the three shells, typing `nihongo kanji <Tab>` shows the
   sub-subcommands `show` and `png` (the children of the `kanji` parser).

Negative test for Fish (file-completion fallback must be disabled): in a
directory containing a file `notes.txt`, typing `nihongo <Tab>` must not list
`notes.txt`.


## Idempotence and Recovery

Every step in this plan is idempotent: re-running `cabal build`, re-running
`nihongo completions <shell> > <path>`, or re-running `git add && git commit` on
unchanged files is safe. The shell-completion install commands overwrite the
target file rather than appending, so re-running them recovers from a corrupted
script.

If a milestone's edit produces a generator that does not match the expected
script, revert that single file with

    git checkout -- nihongo-cli/src/Nihongo/Cli/Completions.hs

and start the milestone again. No external state (database, server, package
registry) is touched, so there is nothing to roll back beyond the working tree.

If installing the completion script breaks the user's interactive shell, remove
the installed file:

    rm -f ~/.local/share/bash-completion/completions/nihongo
    rm -f ~/.zfunc/_nihongo
    rm -f ~/.config/fish/completions/nihongo.fish

and re-source the shell config. The shell will fall back to its defaults.


## Interfaces and Dependencies

This plan touches only the `nihongo-cli` package. No new runtime dependencies are
added; `optparse-applicative` (already a dependency, lower bound `>=0.19`) is the
only library the runtime path uses for the completion protocol.

A test-only dependency on `hspec ^>=2.11` is added — the same major series already
used by `nihongo-core`'s test suite, so the version is consistent with the existing
project pin.

Module-level interface after this change:

- `Nihongo.Cli.Completions` (in `nihongo-cli/src/Nihongo/Cli/Completions.hs`):
  - exposed:
    - `data CompletionsShell = Bash | Zsh | Fish` (unchanged).
    - `completionsCommandParser :: Parser CompletionsShell` (unchanged).
    - `runCompletionsCommand :: CompletionsShell -> IO ()` (unchanged signature; new
      body is `TIO.putStr . completionScript`).
    - `completionScript :: CompletionsShell -> Text` (**new**, pure, returns the
      shell-script text for the given shell).
- `Test.Nihongo.Cli.CompletionsSpec` (in
  `nihongo-cli/test/Test/Nihongo/Cli/CompletionsSpec.hs`): exports `spec :: Spec`.
- `Main` in `nihongo-cli/test/Main.hs`: standard hspec entry point that runs
  `Test.Nihongo.Cli.CompletionsSpec.spec`.

The `nihongo-cli/nihongo-cli.cabal` file gains:

- A new `test-suite nihongo-cli-test` stanza with `hspec`, `nihongo-cli`, and
  `text` as `build-depends`.

The `Nihongo.Cli` module and the `nihongo` executable entry are unchanged: they
already dispatch to `runCompletionsCommand`, whose signature is preserved.
