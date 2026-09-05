{ pkgs
, gitRev
, kanjivg-src
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak dontCheck dontHaddock;
in
final: prev: {
  # kdl-hs 1.0.1 is not yet in nixpkgs (which ships 0.2.1). Fetch from Hackage
  # directly until the shared haskell-nix registry adopts it.
  kdl-hs = dontCheck (doJailbreak (final.callCabal2nix "kdl-hs"
    (builtins.fetchTarball {
      url = "https://hackage.haskell.org/package/kdl-hs-1.0.1/kdl-hs-1.0.1.tar.gz";
      sha256 = "sha256-XlNHId1y8i9OIjId09/W8oup+8Ma+bi6WkmR7MgDqSg=";
    })
    { }));

  # `dontHaddock` below: nihongo ships a CLI, not a library anyone reads Haddock
  # for, and these are exactly the derivations that rebuild on every `nix build`
  # here and on every `darwin-rebuild` in mori://shinzui/dotfiles.nix. nixpkgs'
  # builder defaults `doHaddock` to true, which adds a `doc` output plus a
  # Haddock pass over the package and its dependencies' interfaces — pure
  # repeated cost. Scoped to these packages rather than the whole scope (which
  # is what `disableHaddock = true` on mori://shinzui/haskell-nix's
  # `mkChannelExtension` would do) so the dependency closure keeps its hashes
  # instead of needing a one-time full rebuild.

  nihongo-core = dontHaddock (doJailbreak (final.callCabal2nix "nihongo-core" ../nihongo-core { }));

  nihongo-cli = pkgs.haskell.lib.compose.overrideCabal
    (drv: {
      configureFlags = (drv.configureFlags or [ ]) ++ [
        "--ghc-option=-DGIT_HASH=\"${builtins.substring 0 7 gitRev}\""
      ];
      # Bake the KanjiVG corpus location into the binary so `nihongo` works
      # from any cwd. `--set-default` keeps the runtime resolution priority
      # honest: an explicit `--kanjivg-dir` flag still wins, and a user-set
      # NIHONGO_KANJIVG_DIR still overrides this default.
      buildTools = (drv.buildTools or [ ]) ++ [ pkgs.makeWrapper ];
      postInstall = (drv.postInstall or "") + ''
        wrapProgram $out/bin/nihongo \
          --set-default NIHONGO_KANJIVG_DIR ${kanjivg-src}
      '';
    })
    (dontHaddock (doJailbreak (final.callCabal2nix "nihongo-cli" ../nihongo-cli { })));
}
