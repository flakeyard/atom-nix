# devShells.flakeyard-nix: the tools of the domain for people (FY-0017);
# atom-workspace joins it into devShells.default.
{ warning }:
{
  _file = ./shell.nix;

  config.perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings) hooks;
    in
    {
      devShells.flakeyard-nix = warning pkgs.lib (
        pkgs.mkShellNoCC {
          packages = [
            config.treefmt.programs.nixfmt.package
            hooks.statix.package
            hooks.deadnix.package
            hooks.flakeyard-nix-relative-paths.package
          ];
        }
      );
    };
}
