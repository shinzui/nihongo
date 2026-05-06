# nihongo

> A terminal-first Japanese learning companion for kanji, vocabulary, reading, and daily study workflows.

A terminal-first Japanese learning companion for studying kanji, vocabulary, readings, stroke order, and grammar directly from the command line, designed for fast, keyboard-driven workflows and daily practice.

## Layout

This project is split into two cabal packages:

- **`nihongo-core`** — the library. Domain types, business logic, and
  the project-wide `Nihongo.Prelude` that re-exports
  [`lens`](https://hackage.haskell.org/package/lens) and
  [`generic-lens`](https://hackage.haskell.org/package/generic-lens).
- **`nihongo-cli`** — the command-line interface. Exposes
  `Nihongo.Cli.runCli` and ships an executable named
  **`nihongo`** that just calls it.

Both packages target **GHC `ghc912`** with `default-language: GHC2024`
and the same warning set + default extensions
(`DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings`).

## Develop

The project ships a Nix flake (`nix-haskell-flake`) that pins GHC and provides
the dev shell. Enter the shell with:

```bash
nix develop      # or: direnv allow, if you use direnv
```

Then build and run:

```bash
cabal build all
cabal run nihongo -- hello --name world
```

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

## License

[BSD-3-Clause](./LICENSE) — (c) 2026 Nadeem Bitar.
