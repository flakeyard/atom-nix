# fixture: the flake of a project in dev/fixtures/<name> that imports the atom
# as consumers do, and module, the project's own settings. The atom gets this
# flake's treefmt-nix and git-hooks, as with follows, unless they are given.
{ inputs, root, ... }:
{
  _module.args.fixture =
    {
      name,
      treefmt-nix ? inputs.treefmt-nix,
      git-hooks ? inputs.git-hooks,
      module ? { },
    }:
    inputs.flake-parts.lib.mkFlake
      {
        inputs = inputs // {
          self = {
            outPath = root + "/dev/fixtures/${name}";
            inherit inputs;
          };
        };
      }
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        imports = [
          ((import (root + "/flake.nix")).outputs { inherit treefmt-nix git-hooks; }).flakeModules.default
          module
        ];
        perSystem.pre-commit.check.enable = false;
        # allSystems.<system> exposes the hooks to the tests.
        debug = true;
      };
}
