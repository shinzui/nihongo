{
  description = "CLI to help with studying japanese";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  # Shared Haskell patch management
  inputs.haskell-nix.url = "github:shinzui/haskell-nix";
  inputs.haskell-nix.inputs.nixpkgs.follows = "nixpkgs";

  # KanjiVG SVG corpus, baked into the binary's NIHONGO_KANJIVG_DIR default.
  inputs.kanjivg-src = {
    url = "github:KanjiVG/kanjivg";
    flake = false;
  };

  outputs = { self, nixpkgs, pre-commit-hooks, flake-utils, treefmt-nix, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        ghcVersion = "ghc9122";
        gitRev = self.shortRev or "dirty";

        treefmtEval = treefmt-nix.lib.evalModule pkgs (import ./treefmt.nix { inherit pkgs ghcVersion; });
        formatter = treefmtEval.config.build.wrapper;

        haskellPackages = pkgs.haskell.packages.${ghcVersion}.override {
          overrides = pkgs.lib.composeExtensions
            (inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs)
            (import ./nix/haskell-overlay.nix {
              inherit pkgs gitRev;
              kanjivg-src = inputs.kanjivg-src;
            });
        };
      in
      {
        formatter = formatter;

        packages = {
          nihongo = haskellPackages.nihongo-cli;
          default = haskellPackages.nihongo-cli;
        };

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

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.zlib
            pkgs.just
            pkgs.cabal-install
            pkgs.pkg-config
            pkgs.librsvg
            pkgs.gitMinimal
            (haskellPackages.ghcWithPackages (ps: [
              ps.haskell-language-server
            ]))
          ]
          ++ pkgs.lib.optional false pkgs.process-compose;

          shellHook = ''
            ${self.checks.${system}.pre-commit-check.shellHook}
            export LANG=en_US.UTF-8
          '';
        };
      }
    );
}
