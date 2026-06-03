# Project-specific build wiring for nihongo. Kept out of the generated ./nix
# modules so it is the one place to evolve nihongo's package build.
#
# The nihongo packages are built from a ghc9124 Haskell package set extended with
# two overlays: the shared haskell-nix registry (patch management, e.g. pins that
# nixpkgs hasn't adopted) composed with ./nix/haskell-overlay.nix (kdl-hs 1.0.1
# from Hackage, plus nihongo-core / nihongo-cli with the KanjiVG corpus and the
# git revision baked into the binary).
{ inputs, ... }:
{
  perSystem = { system, pkgs, ... }:
    let
      gitRev = inputs.self.shortRev or "dirty";

      haskellPackages = pkgs.haskell.packages.ghc9124.override {
        overrides = pkgs.lib.composeExtensions
          (inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs)
          (import ./nix/haskell-overlay.nix {
            inherit pkgs gitRev;
            kanjivg-src = inputs.kanjivg-src;
          });
      };
    in
    {
      packages.nihongo = haskellPackages.nihongo-cli;
      packages.default = haskellPackages.nihongo-cli;
    };
}
