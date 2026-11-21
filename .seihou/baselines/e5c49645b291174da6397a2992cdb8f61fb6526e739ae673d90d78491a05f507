# Workspace package outputs for the two-package nihongo CLI scaffold.
# seihou-managed by haskell-cli-app; project-specific customizations still
# belong in the unmanaged ../flake.module.nix imported by the base flake.
{ inputs, ... }:
{
  perSystem = { pkgs, config, ... }:
    let
      haskellPackages = config.haskellProject.applicationScope;
      corePackage = haskellPackages."nihongo-core";
      cliPackage = haskellPackages."nihongo-cli";
    in
    {
      haskellProject.ownPackages = [ "nihongo-core" "nihongo-cli" ];
      haskellProject.applicationOverlays = [
        (hself: _hsuper: {
          "nihongo-core" =
            hself.callCabal2nix "nihongo-core"
              (builtins.path {
                path = inputs.self + "/nihongo-core";
                name = "nihongo-core-source";
              })
              { };
          "nihongo-cli" =
            hself.callCabal2nix "nihongo-cli"
              (builtins.path {
                path = inputs.self + "/nihongo-cli";
                name = "nihongo-cli-source";
              })
              { };
        })
      ];
      packages."nihongo-core" = corePackage;
      packages."nihongo-cli" = cliPackage;
      packages.default = cliPackage;
      checks."nihongo-cli-test" = pkgs.haskell.lib.doCheck cliPackage;
    };
}
