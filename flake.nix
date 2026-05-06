{
  description = "CLI to help with studying japanese";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  # Shared Haskell patch management
  inputs.haskell-nix.url = "github:shinzui/haskell-nix";

  outputs = { self, nixpkgs, pre-commit-hooks, flake-utils, treefmt-nix, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        ghcVersion = "ghc9122";
        haskellPackages = pkgs.haskell.packages.${ghcVersion};
      in
      {
        packages = {
          default = haskellPackages.nihongo;
        };

        checks = {
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.zlib
            pkgs.just
            pkgs.cabal-install
            pkgs.pkg-config
            pkgs.librsvg
            pkgs.gitMinimal
            (pkgs.haskell.packages.${ghcVersion}.ghcWithPackages (ps: [
              ps.haskell-language-server
            ]))
          ]
          ++ pkgs.lib.optional false pkgs.process-compose;

          shellHook = ''
            export LANG=en_US.UTF-8
          '';
        };
      }
    );
}
