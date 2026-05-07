{ pkgs
, gitRev
, kanjivg-src
}:
let
  inherit (pkgs.haskell.lib.compose) doJailbreak dontCheck;
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

  nihongo-core = doJailbreak (final.callCabal2nix "nihongo-core" ../nihongo-core { });

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
    (doJailbreak (final.callCabal2nix "nihongo-cli" ../nihongo-cli { }));
}
