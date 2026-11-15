# The formatter nixfmt of treefmt-nix. Formatting is checked by
# checks.treefmt of treefmt-nix, which atom-workspace makes substitutable;
# the atom has no formatting check of its own (FY-0017).
{
  _file = ./treefmt.nix;

  config.perSystem =
    { lib, pkgs, ... }:
    {
      treefmt.programs.nixfmt = {
        enable = lib.mkOverride 900 true;
        package = lib.mkOverride 900 pkgs.nixfmt;
      };
    };
}
