---
id: 6
slug: add-nix-build-with-shared-haskell-nix-flake
title: "Add nix build with shared haskell-nix flake"
kind: exec-plan
created_at: 2026-05-06T03:55:30Z
---

# Add nix build with shared haskell-nix flake

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today the repository ships a `flake.nix` whose `packages.default` points at
`haskellPackages.nihongo` — an attribute that does not exist anywhere. There is
no overlay defining it, no `callCabal2nix` invocation, and no GHC version pin
that matches the rest of the author's Haskell CLIs. As a result, `nix build` in
this repository fails with an evaluation error, and downstream consumers have
no reproducible way to install the `nihongo` executable.

After this plan lands, a user with only Nix installed can run, from a fresh
clone of the repository:

    nix build .#nihongo
    ./result/bin/nihongo --version

and see output of the form:

    nihongo 0.1.0.0 (git: <7-char-sha>)

They can also run `nix flake check` and see treefmt formatting and pre-commit
checks pass with no errors. The `devShells.default` shell continues to work
exactly as it does today (cabal, HLS, just, the existing graphics deps), only
now backed by GHC 9.12.2 to match the rest of the author's Haskell projects.

The "common haskell-nix flake" referred to in the task is
[`github:shinzui/haskell-nix`](https://github.com/shinzui/haskell-nix), which
the sibling CLIs **seihou**, **rei**, and **mori** all consume. It is a small
shared flake that bundles cross-cutting Haskell package patches (jailbreaks,
version bounds, the `crypton` / `tls` / `x509` cascade, `hasql-migration`,
etc.) so each downstream project does not need to maintain duplicate overrides.
By adopting it here we (a) get a binary build that mirrors how the author
already ships seihou/rei/mori, and (b) put nihongo on the same patch baseline
so future shared dependencies "just work".


## Progress

- [x] **Milestone A — Bump GHC version and add the shared `haskell-nix` flake input.** (2026-05-06)
  - [x] Edit `flake.nix`: change `ghcVersion` from `ghc912` to `ghc9122`.
  - [x] Edit `flake.nix`: add `inputs.haskell-nix.url = "github:shinzui/haskell-nix"` and the matching `pre-commit-hooks` and `treefmt-nix` inputs.
  - [x] Run `nix flake lock --update-input ...` so `flake.lock` records the new inputs. Locked: haskell-nix `4747cb8` (2026-04-24), pre-commit-hooks `3cfd774` (2026-04-21), treefmt-nix `790751f` (2026-04-08).
  - [x] Verify `nix develop` still drops into a working shell. `ghc --version` → `9.12.2`; `cabal build all` → `Up to date`.

- [x] **Milestone B — Write `nix/haskell-overlay.nix` and wire `packages.nihongo` to a `callCabal2nix` build.** (2026-05-06)
  - [x] Create `nix/haskell-overlay.nix` defining `nihongo-core` and `nihongo-cli` via `final.callCabal2nix`, with `doJailbreak` and the `-DGIT_HASH=...` configure flag.
  - [x] Edit `flake.nix` `outputs`: build `haskellPackages` as `pkgs.haskell.packages.${ghcVersion}.override { overrides = composeExtensions (haskellExtension ...) (import ./nix/haskell-overlay.nix ...); }`.
  - [x] Edit `flake.nix`: replace `packages.default = haskellPackages.nihongo` with `packages.nihongo = haskellPackages.nihongo-cli; packages.default = haskellPackages.nihongo-cli`.
  - [x] **Out-of-plan fix surfaced by the build:** drop `license-file: ../LICENSE` and `extra-doc-files: ../CHANGELOG.md` from both `nihongo-core.cabal` and `nihongo-cli.cabal`. See *Surprises & Discoveries* below.
  - [x] Run `nix build .#nihongo` and `./result/bin/nihongo --version`; output is `nihongo 0.1.0.0 (git: dirty)` (working tree has uncommitted changes during the build, which is the documented `self.shortRev or "dirty"` fallback). `./result/bin/nihongo --help` prints the full subcommand list (hello, help, completions, kanji).

- [x] **Milestone C — Add the `treefmt` formatter, the formatting flake check, and the pre-commit hook check, mirroring seihou.** (2026-05-06)
  - [x] Update `treefmt.nix` to take `{ pkgs, ghcVersion, ... }` so `fourmolu` and `cabal-gild` come from the GHC 9.12.2 package set.
  - [x] Edit `flake.nix`: add the `treefmtEval`/`formatter` lets and expose `formatter`, `checks.formatting`, and `checks.pre-commit-check`.
  - [x] Update stale `cabal.project` comment that still referenced `ghc912`.
  - [x] Run `nix fmt` to normalize the codebase under fourmolu + cabal-gild + nixpkgs-fmt; 21 files reformatted (whitespace, blank-line removal, build-depends alphabetization).
  - [x] Run `nix flake check` — both `formatting` and `pre-commit-check` derivations succeed.
  - [x] Verify the pre-commit hook installs into `.git/hooks/pre-commit` on first `nix develop` entry. Confirmed: `pre-commit installed at .git/hooks/pre-commit`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered
during implementation. Provide concise evidence (short transcripts, diffs).

**Cabal files referenced parent-directory paths that `callCabal2nix` cannot satisfy.** Both `nihongo-core/nihongo-core.cabal` and `nihongo-cli/nihongo-cli.cabal` carried `license-file: ../LICENSE` and `extra-doc-files: ../CHANGELOG.md`. `callCabal2nix` only copies the package directory into the build sandbox, so Cabal's preprocessor failed during the test-suite preparation step:

    Preprocessing test suite 'nihongo-core-tests' for nihongo-core-0.1.0.0...
    Error: [Cabal-6661]
    filepath wildcard '../CHANGELOG.md' does not match any files.

Fix was to drop both `../`-prefixed lines from both cabal files (mori-core/mori-cli use the same pattern: SPDX `license:` line, no `license-file`, no `extra-doc-files`). The `LICENSE` and `CHANGELOG.md` at the repo root remain for humans; cabal just no longer indexes them. The references were also a latent `cabal sdist` hazard — `cabal sdist` requires `extra-doc-files` to live inside the package directory.


## Decision Log

- **Decision:** Bump GHC from `ghc912` to `ghc9122` as part of this plan.
  **Rationale:** The shared `haskell-nix` flake's overlay only patches the
  `ghc9122` and `ghc914` package sets (see `lib/mkHaskellOverlay.nix` in the
  upstream flake; the `forAllSystems` block in its `flake.nix` confirms only
  these two GHCs receive the cross-cutting patches). Staying on `ghc912`
  would mean the author's shared patches silently do not apply, defeating the
  purpose of adopting the shared flake. All sibling CLIs (seihou, rei, mori)
  pin `ghc9122`, so this also brings nihongo onto the same compiler.
  **Date:** 2026-05-06.

- **Decision:** Do **not** plumb the `data/kanjivg` git submodule into the nix
  build. **Rationale:** Audit of `nihongo-core/src/Nihongo/Kanji/KanjiVg.hs`
  and the CLI's `Nihongo.Cli.Commands.KanjiDebug` shows the KanjiVG corpus is
  resolved purely at **runtime** via an explicit override, the
  `NIHONGO_KANJIVG_DIR` env var, or `<cwd>/data/kanjivg`. There are no
  Template Haskell `embedDir`/`embedFile` splices that pull from the
  submodule, and the `nihongo-core` test suite uses its own fixtures under
  `nihongo-core/test/fixtures/`. Adding a submodule input to the flake would
  be inert weight; users who need stroke-order data continue to populate it
  from outside the nix-built binary. **Date:** 2026-05-06.

- **Decision:** Do not adopt seihou's `cli-module-placement` custom hook or
  rei's PostgreSQL/process-compose dev-shell extras. **Rationale:** Those are
  project-specific to seihou's module layout and rei's persistent storage
  needs respectively. nihongo today has neither requirement. Keep the scope
  of this plan to the **common** pattern: shared `haskell-nix` overlay,
  `callCabal2nix` builds, and treefmt + pre-commit checks. **Date:**
  2026-05-06.

- **Decision:** Mirror **seihou** specifically as the reference for this
  plan, rather than rei or mori. **Rationale:** seihou is the only one of
  the three with no private GitHub source dependencies (`tan-event-source`,
  `message-db-hs`, `tan-commons`, `tan-effectful`, `typeid-hs`,
  `mori-schema`). nihongo likewise has none. Copying seihou's structure
  yields the shortest, least-surprising flake. **Date:** 2026-05-06.

- **Decision:** Drop `license-file: ../LICENSE` and
  `extra-doc-files: ../CHANGELOG.md` from `nihongo-core.cabal` and
  `nihongo-cli.cabal` rather than copy those files into the sandbox via
  `prePatch`. **Rationale:** mori-core/mori-cli show the cleaner pattern —
  SPDX `license:` only, no `license-file:`, no `extra-doc-files:`. The
  `../` references were both a nix-build blocker and a latent `cabal sdist`
  hazard; copying via `prePatch` would mask the smell. The LICENSE and
  CHANGELOG remain at the repo root for humans. **Date:** 2026-05-06.


## Outcomes & Retrospective

**What was achieved.** A novice with only Nix can clone the repo and run
`nix build .#nihongo` to get a working `./result/bin/nihongo` executable.
The binary's `--version` reports `nihongo 0.1.0.0 (git: <sha>)` (or
`(git: dirty)` against an unclean tree), driven by the shared
`-DGIT_HASH=...` CPP fallback in `Nihongo.Cli.Version`. `nix flake check`
passes both `formatting` (treefmt drift check) and `pre-commit-check`
(cachix/pre-commit-hooks.nix). The pre-commit hook auto-installs into
`.git/hooks/` on first `nix develop` entry. The repository now sits on the
same `github:shinzui/haskell-nix` patch baseline as seihou, rei, and mori.

**Gaps / what remains.** None for this plan's stated scope. Future work
that may want to bolt on:
- A `cabal-fmt` → `cabal-gild` formatter swap commit will reorder/strip
  blank lines in cabal files; that drift is now permanently caught by the
  `formatting` check.
- ~~If KanjiVG ever needs to be embedded into the binary (rather than
  resolved at runtime), the overlay would need a `prePatch` that copies
  `data/kanjivg/kanji/` into the build sandbox via a flake input.~~
  Done in the **post-plan extension** below.

**Post-plan extension (2026-05-06): bake KanjiVG corpus into the binary.**

Added `inputs.kanjivg-src = { url = "github:KanjiVG/kanjivg"; flake = false; }`
to `flake.nix` and a `wrapProgram` postInstall in `nix/haskell-overlay.nix`:

    wrapProgram $out/bin/nihongo \
      --set-default NIHONGO_KANJIVG_DIR ${kanjivg-src}

The wrapper makes `pkgs.nihongo` self-contained — `nihongo kanji show 漢`
works from any cwd with no env var set, while still honouring
`--kanjivg-dir <path>` (priority 1) and a user-set `NIHONGO_KANJIVG_DIR`
(priority 2, overrides the baked default because `--set-default` only
sets if unset). Verified from `/tmp` with the corpus rendered correctly,
and from `/tmp` with `NIHONGO_KANJIVG_DIR=/nonexistent` failing as
expected — proves the override hierarchy still works.

This unblocks adding the nihongo flake to the user's dotfiles
(`/Users/shinzui/.config/dotfiles.nix/flake.nix`) as a global package
without any working-tree-pinned env-var coupling.

**Lessons learned.**
1. `callCabal2nix` only copies the named package directory into the build
   sandbox. Any cabal-file reference to a sibling or parent path (`license-file: ../LICENSE`, `extra-doc-files: ../CHANGELOG.md`) breaks the
   build. The right fix is to stop referencing `../` from cabal files; the
   files at the repo root remain available to humans without being indexed
   by Cabal.
2. Nix flakes only see git-tracked files. Adding a new file (e.g.
   `nix/haskell-overlay.nix`) requires `git add` before the next
   `nix build`/`nix flake check`, even without committing.
3. The shared `haskell-nix` flake's `lib.haskellExtension` actually has the
   signature `haskellLib -> pkgs -> hself -> hsuper -> attrs` (its README
   shows the older `haskellLib -> hself -> hsuper -> attrs` form). The
   correct call site is `inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs`, exactly as seihou and mori do it.
4. The `(git: dirty)` suffix is correct behaviour, not a bug — it reflects
   `self.shortRev or "dirty"`. A clean checkout produces a real SHA.


## Context and Orientation

This repository is a Haskell monorepo for a terminal-first Japanese learning
companion. Its layout, by full repository-relative path:

- `cabal.project` — Cabal project descriptor; lists the two packages.
- `nihongo-core/` — Library: domain types, KanjiVG resolution, prelude.
  - `nihongo-core/nihongo-core.cabal` — Cabal file; library + `nihongo-core-tests` test-suite (hspec).
  - `nihongo-core/src/Nihongo/...` — Library source.
  - `nihongo-core/test/` — Hspec tests; fixtures under `nihongo-core/test/fixtures/`.
- `nihongo-cli/` — Library + executable that ships the `nihongo` CLI.
  - `nihongo-cli/nihongo-cli.cabal` — Cabal file; library + `executable nihongo`.
  - `nihongo-cli/app/Main.hs` — Executable entry point.
  - `nihongo-cli/src/Nihongo/Cli/Version.hs` — **Critical for this plan.** Contains a `{-# LANGUAGE CPP #-}` `#ifdef GIT_HASH` fallback that compiles the SHA in via `-DGIT_HASH=...` when the build sandbox strips `.git` (i.e. nix builds). The matching runtime path uses `githash`'s `tGitInfoCwdTry` for cabal-from-checkout builds.
  - `nihongo-cli/help/` — Markdown help text bundled at compile time via `file-embed`.
- `flake.nix` — **Currently broken.** References `haskellPackages.nihongo` which is never defined; `pkgs.haskell.packages."ghc912"` has no overlay attaching a `nihongo` attribute. `nix build` in this repo therefore fails today.
- `flake.lock` — Currently locks only `nixpkgs` and `flake-utils`.
- `treefmt.nix` — Existing minimal config: `nixpkgs-fmt`, `fourmolu`, `cabal-fmt`. Takes `{ pkgs, ... }` and ignores `ghcVersion`.
- `data/kanjivg/` — Git submodule containing the KanjiVG corpus. Used purely at runtime; **not** part of the nix build.
- `docs/plans/` — Where ExecPlans (this file included) live.

**Terms of art used in this plan, defined plainly:**

- **Flake** — A Nix project descriptor (`flake.nix` + `flake.lock`) that
  declares its inputs (other repositories, pinned by hash) and its outputs
  (packages, dev shells, checks). It produces fully reproducible builds: the
  same flake on the same Nix version yields byte-identical results.

- **Overlay** — A function `final: prev: { ... }` that extends a Nix package
  set. The `prev` argument is the unmodified set; `final` is the eventually
  overridden set, used so attributes can refer to each other after override.
  An overlay can replace, wrap, or add packages.

- **`callCabal2nix`** — A function in nixpkgs' Haskell infrastructure. Given
  a name and a path containing a `.cabal` file, it generates a Nix derivation
  that builds the package. Critically, it **only copies that package's
  directory** into the build sandbox; sibling packages and the project root
  must be wired up by hand if they are needed during the build.

- **`doJailbreak`** — A nixpkgs Haskell helper that strips upper version
  bounds from a package's Cabal file at build time. Useful when a dependency
  has a stale upper bound that would otherwise reject the version available
  in the current GHC's package set.

- **`pre-commit-hooks.nix`** — A flake from cachix that turns a Nix-defined
  set of hooks into a `git` pre-commit hook installer. The `shellHook` it
  exposes is sourced from `devShells.default` so the hooks auto-install when
  a developer first runs `nix develop`.

- **`treefmt-nix`** — A flake from numtide that wraps the `treefmt` formatter
  multiplexer in Nix. We use it to drive `nixpkgs-fmt`, `fourmolu`, and
  `cabal-gild` from a single `nix fmt` invocation, and to expose a
  `checks.formatting` derivation that fails CI if the tree is not formatted.

- **The shared `haskell-nix` flake** — `github:shinzui/haskell-nix`. A small
  flake that exposes `lib.haskellExtension`, an overlay function carrying
  cross-cutting GHC 9.12.2 / 9.14 patches. The signature, inferred from its
  `flake.nix`, is `haskellLib -> pkgs -> hself -> hsuper -> attrs`; downstream
  consumers compose it with their own local overlay using
  `lib.composeExtensions`.


## Plan of Work

The work decomposes into three milestones, each independently verifiable and
each leaving the repository in a working state.


### Milestone A — Bump GHC and add the shared flake inputs

**Scope.** Pull in the three flake inputs that the seihou-style build
relies on (`pre-commit-hooks`, `treefmt-nix`, `haskell-nix`) and bump
`ghcVersion` from `ghc912` to `ghc9122`. Do **not** yet rewire `packages` —
the goal here is to update the input layer and confirm `nix develop` still
works on the new GHC.

**What will exist at the end.**

- `flake.nix` declares the four inputs `nixpkgs`, `flake-utils`,
  `pre-commit-hooks`, `treefmt-nix`, `haskell-nix`.
- `ghcVersion` is `"ghc9122"`.
- `flake.lock` contains entries for the three new inputs.
- `nix develop` still drops into a working dev shell; cabal can build all
  packages from inside that shell.

**Concrete edits.** In `flake.nix`:

1. Replace the `inputs` block with:

        inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
        inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
        inputs.flake-utils.url = "github:numtide/flake-utils";
        inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

        # Shared Haskell patch management
        inputs.haskell-nix.url = "github:shinzui/haskell-nix";

2. Change the `outputs` parameter list to destructure the new inputs, mirroring seihou:

        outputs = { self, nixpkgs, pre-commit-hooks, flake-utils, treefmt-nix, ... }@inputs:

3. Inside the `let`, add `ghcVersion = "ghc9122";` and replace
   `haskellPackages = pkgs.haskell.packages."ghc912"` with
   `haskellPackages = pkgs.haskell.packages.${ghcVersion}` (we will rebuild
   this expression in Milestone B; the goal here is just that `nix develop`
   continues to evaluate against the new GHC).

4. Inside `devShells.default.nativeBuildInputs`, switch the `haskellPackages.ghcWithPackages` line to `pkgs.haskell.packages.${ghcVersion}.ghcWithPackages` so it tracks `ghcVersion` symbolically.

**Acceptance.**

- `nix develop --command ghc --version` prints `The Glorious Glasgow Haskell Compilation System, version 9.12.2`.
- `nix develop --command cabal build all` succeeds (this is the existing path that works today; it must continue to work after the bump).


### Milestone B — Write the local overlay and rewire `packages.nihongo`

**Scope.** Add `nix/haskell-overlay.nix`. Build `haskellPackages` by
composing the shared `haskellExtension` with the local overlay. Expose
`packages.nihongo` and `packages.default` as the resulting `nihongo-cli`
derivation. The CLI must build under the nix sandbox and report a git SHA
in `--version` via the `-DGIT_HASH=...` configure flag (the runtime
`tGitInfoCwdTry` path in `Nihongo.Cli.Version` will return `Left` because
`.git` is stripped by the sandbox; the CPP fallback we wire here covers it).

**What will exist at the end.**

- A new file `nix/haskell-overlay.nix` defining `nihongo-core` and
  `nihongo-cli` via `callCabal2nix`.
- `flake.nix` builds `haskellPackages` as a composed override and exposes
  `packages.nihongo` and `packages.default`.
- `nix build .#nihongo` produces `./result/bin/nihongo`.
- `./result/bin/nihongo --version` prints `nihongo 0.1.0.0 (git: <7-char-sha>)`
  when built from a clean checkout (the SHA is `dirty` if `self.shortRev` is
  unavailable, e.g. with uncommitted changes; this is fine and matches how
  seihou and mori behave).

**Concrete edits.**

1. Create `nix/haskell-overlay.nix` with:

        { pkgs
        , gitRev
        }:
        let
          inherit (pkgs.haskell.lib.compose) doJailbreak;
        in
        final: prev: {
          nihongo-core = doJailbreak (final.callCabal2nix "nihongo-core" ../nihongo-core { });

          nihongo-cli = pkgs.haskell.lib.compose.overrideCabal
            (drv: {
              configureFlags = (drv.configureFlags or [ ]) ++ [
                "--ghc-option=-DGIT_HASH=\"${builtins.substring 0 7 gitRev}\""
              ];
            })
            (doJailbreak (final.callCabal2nix "nihongo-cli" ../nihongo-cli { }));
        }

   The `../nihongo-core` and `../nihongo-cli` paths are resolved relative to
   `nix/haskell-overlay.nix`, so they refer to the package directories at the
   repository root. `callCabal2nix` only copies the named directory into the
   sandbox, which is fine for this project — the `nihongo-core` test suite's
   fixtures live inside `nihongo-core/test/fixtures/`, not at the project
   root, so they are copied automatically.

2. In `flake.nix`, replace the existing `let` body so the relevant region
   reads as follows. (Show the diff in prose: the new shape mirrors
   `seihou-project/seihou/flake.nix` lines 19–47.)

        let
          pkgs = import nixpkgs { inherit system; };
          ghcVersion = "ghc9122";
          gitRev = self.shortRev or "dirty";

          haskellPackages = pkgs.haskell.packages.${ghcVersion}.override {
            overrides = pkgs.lib.composeExtensions
              (inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs)
              (import ./nix/haskell-overlay.nix {
                inherit pkgs gitRev;
              });
          };
        in

3. Replace the `packages` attrset to:

        packages = {
          nihongo = haskellPackages.nihongo-cli;
          default = haskellPackages.nihongo-cli;
        };

   (Drop the broken `haskellPackages.nihongo` reference.)

**Acceptance.**

From the repository root, run:

    nix build .#nihongo

The build should succeed with no errors. Then:

    ./result/bin/nihongo --version

Expected output (the SHA will differ; the surrounding form must match):

    nihongo 0.1.0.0 (git: 416bcbe)

If the working tree is dirty at build time, expect `dirty` in place of the
SHA — that is the documented `self.shortRev or "dirty"` fallback and is
acceptable.

Also run:

    ./result/bin/nihongo --help

Expected: a non-empty help screen listing the available subcommands. This
proves the executable was actually linked and started, not merely compiled.


### Milestone C — Wire `treefmt`, formatting check, and pre-commit hook

**Scope.** Bring the `nix flake check` surface up to parity with
seihou: a `formatter` output, a `checks.formatting` derivation that fails
when the tree is unformatted, and a `checks.pre-commit-check` that installs
itself into `.git/hooks` via the `devShells.default` `shellHook`.

**What will exist at the end.**

- `treefmt.nix` accepts `{ pkgs, ghcVersion, ... }` and pulls `fourmolu` and
  `cabal-gild` from the GHC 9.12.2 package set so they match the compiler
  used for builds. (`cabal-gild` replaces the existing `cabal-fmt` to match
  seihou; both produce equivalent output, but `cabal-gild` is what the rest
  of the author's projects use.)
- `flake.nix` exposes `formatter`, `checks.formatting`, and
  `checks.pre-commit-check`.
- `nix flake check` passes.
- `nix develop` installs the pre-commit hook into the local `.git/hooks` on
  first entry.

**Concrete edits.**

1. Replace `treefmt.nix` with:

        { pkgs, ghcVersion, ... }:
        let
          haskellPkgs = pkgs.haskell.packages."${ghcVersion}";
        in
        {
          projectRootFile = "flake.nix";
          programs.nixpkgs-fmt.enable = true;
          programs.fourmolu.enable = true;
          programs.fourmolu.package = haskellPkgs.fourmolu;
          programs.cabal-gild.enable = true;
          programs.cabal-gild.package = haskellPkgs.cabal-gild;
        }

2. In `flake.nix`'s `let` block, add after `gitRev`:

        treefmtEval = treefmt-nix.lib.evalModule pkgs (import ./treefmt.nix { inherit pkgs ghcVersion; });
        formatter = treefmtEval.config.build.wrapper;

3. Add `formatter = formatter;` to the per-system outputs.

4. Replace the empty `checks = { };` block with:

        checks = {
          formatting = treefmtEval.config.build.check self;
          pre-commit-check = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              treefmt.package = formatter;
              treefmt.enable = true;
            };
          };
        };

5. In `devShells.default.shellHook`, prepend the existing `LANG` export with:

        ${self.checks.${system}.pre-commit-check.shellHook}

**Acceptance.**

From the repository root:

    nix flake check

Expected: completes with no error output. If treefmt reports drift
(`error: builder for '/nix/store/...-formatting-check.drv' failed`), run
`nix fmt`, inspect the diff, commit the formatting changes, and re-run
`nix flake check`. It must pass before this milestone is considered done.

Also:

    nix develop --command true

After this command runs once, `cat .git/hooks/pre-commit` should exist and
reference the treefmt formatter. (This proves the `pre-commit-check.shellHook`
installation step ran; do not assert on its exact contents, which differ by
`pre-commit-hooks.nix` version.)


## Concrete Steps

Run each block from the repository root,
`/Users/shinzui/Keikaku/bokuno/nihongo/`. Commit between milestones; each
commit must include the trailer

    ExecPlan: docs/plans/6-add-nix-build-with-shared-haskell-nix-flake.md

per the ExecPlan skill's git-trailer rule.

**Milestone A.**

1. Edit `flake.nix` per the steps in *Plan of Work — Milestone A*.

2. Update the lockfile to fetch the new inputs:

        nix flake lock --update-input pre-commit-hooks --update-input treefmt-nix --update-input haskell-nix

   Expected output ends with three `Added input '<name>'` lines and re-prints
   the locked revisions. If `--update-input` is rejected (older Nix), use
   `nix flake update` instead, which will re-resolve all inputs.

3. Smoke-test the dev shell:

        nix develop --command ghc --version
        nix develop --command cabal build all

   Expected: the first prints `... version 9.12.2`. The second prints the
   familiar cabal build progress and ends with `Linking ... nihongo` or
   `Up to date`.

4. Commit:

        git add flake.nix flake.lock
        git commit -m "$(cat <<'EOF'
        feat(nix): EP-6 Milestone A — bump GHC to 9.12.2, add haskell-nix flake input

        Switch ghcVersion from ghc912 to ghc9122 to match the GHC pinned by
        the shared github:shinzui/haskell-nix overlay (which only patches
        ghc9122 and ghc914). Add the pre-commit-hooks, treefmt-nix, and
        haskell-nix inputs in preparation for the overlay-driven build in
        Milestone B.

        ExecPlan: docs/plans/6-add-nix-build-with-shared-haskell-nix-flake.md
        EOF
        )"

**Milestone B.**

1. Create `nix/` and write `nix/haskell-overlay.nix` per *Plan of Work — Milestone B*:

        mkdir -p nix
        # then create the file with the contents shown in Plan of Work

2. Edit `flake.nix` to compose `haskellPackages` and rewire `packages` per *Plan of Work — Milestone B*.

3. Build and exercise the binary:

        nix build .#nihongo
        ./result/bin/nihongo --version
        ./result/bin/nihongo --help

   Expected first line of `--version`:

        nihongo 0.1.0.0 (git: <sha>)

   `--help` should print a non-empty usage screen.

4. Commit:

        git add flake.nix nix/haskell-overlay.nix
        git commit -m "$(cat <<'EOF'
        feat(nix): EP-6 Milestone B — build nihongo-cli via callCabal2nix overlay

        Add nix/haskell-overlay.nix defining nihongo-core and nihongo-cli via
        callCabal2nix, and rewire flake.nix to compose the shared haskell-nix
        haskellExtension with the local overlay. Inject -DGIT_HASH so the CPP
        fallback in Nihongo.Cli.Version reports the short SHA when .git is
        stripped by the nix sandbox.

        After this commit, `nix build .#nihongo` produces ./result/bin/nihongo
        and `./result/bin/nihongo --version` reports the version + git suffix.

        ExecPlan: docs/plans/6-add-nix-build-with-shared-haskell-nix-flake.md
        EOF
        )"

**Milestone C.**

1. Replace `treefmt.nix` per *Plan of Work — Milestone C*.

2. Edit `flake.nix` to expose `formatter`, `checks.formatting`,
   `checks.pre-commit-check`, and prepend the pre-commit shellHook to
   `devShells.default.shellHook`.

3. Run the formatter and the flake check:

        nix fmt
        git status   # inspect any formatting drift
        # If drift exists, commit the formatting changes here.
        nix flake check

   Expected: `nix flake check` exits 0 with no error output.

4. Verify the pre-commit hook installs into `.git/hooks`:

        nix develop --command true
        ls .git/hooks/pre-commit

   Expected: the file exists.

5. Commit (two commits if formatting drift required a separate commit;
   otherwise one):

        git add flake.nix treefmt.nix
        git commit -m "$(cat <<'EOF'
        feat(nix): EP-6 Milestone C — wire treefmt formatter and pre-commit checks

        Mirror seihou's nix flake check surface: expose `formatter`,
        `checks.formatting` (treefmt drift), and `checks.pre-commit-check`
        (cachix/pre-commit-hooks.nix). Auto-install the pre-commit hook via
        the devShell shellHook. Switch cabal-fmt to cabal-gild to match the
        rest of the author's Haskell projects.

        ExecPlan: docs/plans/6-add-nix-build-with-shared-haskell-nix-flake.md
        EOF
        )"


## Validation and Acceptance

A novice can prove this plan succeeded by running, from the repository root,
in this order:

1. **Build proof.**

        nix build .#nihongo
        ./result/bin/nihongo --version

   Expected:

        nihongo 0.1.0.0 (git: <7-char-sha>)

   (`<7-char-sha>` is `dirty` if the working tree has uncommitted changes.)

2. **Help proof — proves the binary actually runs, not just compiles.**

        ./result/bin/nihongo --help

   Expected: a non-empty help screen with at least the `kanji-debug-path`
   subcommand visible (it is the only subcommand currently registered; see
   `nihongo-cli/src/Nihongo/Cli/Commands/KanjiDebug.hs`).

3. **Test proof — the library tests still run inside the cabal-driven dev shell.**

        nix develop --command cabal test all

   Expected: hspec output ending with a non-zero pass count and `0 failures`.

4. **Flake check proof.**

        nix flake check

   Expected: exits 0; no error lines. Specifically the `formatting` and
   `pre-commit-check` derivations should both succeed.

5. **Pre-commit hook proof.**

        nix develop --command true
        cat .git/hooks/pre-commit | head -3

   Expected: a non-empty hook script. The first line is typically
   `#!/usr/bin/env bash` or similar.

If any of these steps produces unexpected output, do **not** mark the
corresponding Milestone item complete in the Progress section. Diagnose,
fix, and re-run.


## Idempotence and Recovery

Every step in this plan is safe to repeat:

- `nix flake lock --update-input` is idempotent: re-running it with the same
  upstream commits leaves the lockfile unchanged.
- `nix build .#nihongo` is content-addressed; repeated runs short-circuit on
  the cached store path.
- `nix flake check` is similarly idempotent.
- The two new files (`nix/haskell-overlay.nix`, the rewritten `flake.nix`,
  the rewritten `treefmt.nix`) are pure additions/rewrites; if a step needs
  to be redone, simply edit the file again and re-run the build.
- The `result` symlink at the repository root is harmless leftover from
  `nix build`. It is already in `.gitignore` (`result\nresult-*`) so it
  cannot be accidentally committed.

If a milestone goes wrong partway, recovery is `git restore -- <file>` on
the affected files (only when the changes are not yet committed) or
`git revert <sha>` if the bad change has already been committed. The
KanjiVG submodule must not be touched by this plan; if `git status` ever
shows changes under `data/kanjivg/`, restore them with
`git submodule update -- data/kanjivg` before continuing.

If `nix flake check` surfaces formatting drift introduced by switching from
`cabal-fmt` to `cabal-gild` (the two tools reformat slightly differently),
the safe response is `nix fmt` followed by a separate commit recording only
the formatting normalisation, then re-run `nix flake check`.


## Interfaces and Dependencies

**External dependencies introduced by this plan:**

- `github:cachix/pre-commit-hooks.nix` — provides
  `pre-commit-hooks.lib.${system}.run`, which yields a derivation that both
  acts as a flake check and produces a `shellHook` that installs the hook
  into `.git/hooks`.
- `github:numtide/treefmt-nix` — provides
  `treefmt-nix.lib.evalModule pkgs config`, which evaluates a `treefmt`
  module and produces `config.build.wrapper` (the formatter) and
  `config.build.check src` (the drift-check derivation).
- `github:shinzui/haskell-nix` — the central piece of this plan. Provides
  `lib.haskellExtension` with signature
  `haskellLib -> pkgs -> hself -> hsuper -> attrs`. We feed it
  `pkgs.haskell.lib.compose` and `pkgs`, then compose its output with our
  local overlay using `pkgs.lib.composeExtensions`.

**Local module that this plan must produce, with its exact interface:**

- `nix/haskell-overlay.nix` — a function with signature

        { pkgs, gitRev } -> final -> prev -> {
          nihongo-core = ...;
          nihongo-cli  = ...;
        }

  Both attributes must be `derivation`s built via `final.callCabal2nix`.
  `nihongo-cli` must additionally pass `--ghc-option=-DGIT_HASH="<sha>"` as
  a configure flag, where `<sha>` is `builtins.substring 0 7 gitRev`. This
  is the exact pattern seihou uses; the CPP fallback in
  `nihongo-cli/src/Nihongo/Cli/Version.hs` lines 35–39 consumes it.

**Existing modules touched, with the contracts they must continue to honour
after this plan:**

- `flake.nix` — must expose `packages.nihongo`, `packages.default`,
  `devShells.default`, `checks.formatting`, `checks.pre-commit-check`, and
  `formatter` for every system in `flake-utils.lib.eachDefaultSystem`. The
  dev shell must continue to provide `cabal-install`, `just`, the existing
  graphics deps (`zlib`, `pkg-config`, `librsvg`, `gitMinimal`), and HLS
  via `ghcWithPackages`.

- `treefmt.nix` — must expose `projectRootFile = "flake.nix";` and at least
  the `nixpkgs-fmt`, `fourmolu`, and `cabal-gild` programs. Additional
  programs may be added later; this plan does not enable them.

- `nihongo-cli/src/Nihongo/Cli/Version.hs` — **no edits.** The CPP `#ifdef
  GIT_HASH` machinery is already in place from a prior milestone and is
  exactly what the new overlay's `-DGIT_HASH=...` flag feeds. If a future
  contributor removes this CPP block, the nix build will silently lose its
  git-SHA suffix; document that with a code comment if it ever changes.
