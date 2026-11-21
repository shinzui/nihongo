# Project-specific flake-parts wiring for nihongo. seihou never generates or
# migrates this file (see flake.module.nix.example for the upstream reference).
#
# The nihongo packages are built in the checked application scope declared by
# ./nix/haskell.nix (ghc9124 package set), extended with two overlays: the shared
# haskell-nix registry (patch management, e.g. pins that nixpkgs hasn't adopted)
# followed by ./nix/haskell-overlay.nix (kdl-hs 1.0.1 from Hackage, plus
# nihongo-core / nihongo-cli with the KanjiVG corpus and the git revision baked
# into the binary). Production packages are selected from that same scope.
{ inputs, ... }:
{
  perSystem = { pkgs, config, ... }:
    let
      gitRev = inputs.self.shortRev or "dirty";
      nihongo = config.haskellProject.applicationScope.nihongo-cli;
    in
    {
      haskellProject = {
        # Native tools for the dev shell: rsvg-convert for stroke-order images,
        # git for the GIT_HASH baked in by cabal builds.
        extraDevPackages = [
          pkgs.librsvg
          pkgs.gitMinimal
        ];

        ownPackages = [ "nihongo-core" "nihongo-cli" ];
        applicationOverlays = [
          (inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs)
          (import ./nix/haskell-overlay.nix {
            inherit pkgs gitRev;
            kanjivg-src = inputs.kanjivg-src;
          })
        ];
      };

      packages.nihongo = nihongo;
      packages.default = nihongo;
    };
}
