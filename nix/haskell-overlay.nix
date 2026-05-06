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
