# checks.nix: the hooks statix, deadnix and flakeyard-nix-relative-paths, as
# the project's configuration holds them (FY-0017). Built with
# lib.<system>.run of git-hooks.nix from only these hooks and the project's
# global excludes, so pre-commit selects the files by `files`, `types` and
# `excludes` as the installed hook does.
{ git-hooks, warning }:
{ self, ... }:
{
  _file = ./checks.nix;

  config.perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      inherit (pkgs) lib;
      inherit (config.pre-commit) settings;
      names = [
        "statix"
        "deadnix"
        "flakeyard-nix-relative-paths"
      ];
      # Every option of the project's hook; raw is computed from the others.
      hook = name: removeAttrs settings.hooks.${name} [ "raw" ];
    in
    {
      checks.nix = warning lib (
        git-hooks.lib.${system}.run {
          src = import ./files.nix {
            inherit lib self;
            domain = map (name: settings.hooks.${name}) names;
          };
          hooks = lib.genAttrs names hook;
          inherit (settings) excludes package gitPackage;
        }
      );
    };
}
