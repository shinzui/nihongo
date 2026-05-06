{ pkgs
, gitRev
, kanjivg-src
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
