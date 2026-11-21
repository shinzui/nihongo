# Project-specific flake-parts wiring for nihongo. seihou never generates or
# migrates this file (see flake.module.nix.example for the upstream reference).
#
# The managed ./nix/haskell-cli-app.nix (haskell-cli-app) declares the
# nihongo-core / nihongo-cli packages, packages.default and the test check, all
# selected from the checked application scope of ./nix/haskell.nix. This module
# appends two overlays to that scope, after the managed one: the shared
# haskell-nix registry (patch management, e.g. pins that nixpkgs hasn't adopted)
# and ./nix/haskell-overlay.nix (kdl-hs 1.0.1 from Hackage, plus the KanjiVG
# corpus and git revision baked into nihongo-cli).
{ inputs, ... }:
{
  perSystem = { pkgs, config, ... }:
    let
      gitRev = inputs.self.shortRev or "dirty";
    in
    {
      haskellProject = {
        # Native tools for the dev shell: rsvg-convert for stroke-order images,
        # git for the GIT_HASH baked in by cabal builds.
        extraDevPackages = [
          pkgs.librsvg
          pkgs.gitMinimal
        ];

        applicationOverlays = [
          (inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs)
          (import ./nix/haskell-overlay.nix {
            inherit pkgs gitRev;
            kanjivg-src = inputs.kanjivg-src;
          })
        ];
      };

      # Stable alias for consumers that reference `.#nihongo`.
      packages.nihongo = config.haskellProject.applicationScope.nihongo-cli;
    };
}
