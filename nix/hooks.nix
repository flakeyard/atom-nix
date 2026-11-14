# The hooks statix and deadnix of git-hooks.nix, with the configuration that
# the project chose (FY-0037). Their files, packages and arguments are the
# single definition that the check of the domain also runs.
{ root }:
{ self, ... }:
{
  _file = ./hooks.nix;

  config.perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.pre-commit.settings.hooks) statix;
      # The project's statix.toml at the root, else the default of the atom;
      # either one as a store path of its own.
      statixConfig =
        if builtins.pathExists (self.outPath + "/statix.toml") then
          builtins.path {
            path = self.outPath + "/statix.toml";
            name = "statix.toml";
          }
        else
          builtins.path {
            path = root + "/config/statix.toml";
            name = "statix.toml";
          };
      # statix check takes one file or directory and knows nothing of the
      # excludes of pre-commit. This runs statix check with the arguments
      # before -- on each file after it, the files that pre-commit selects.
      statixFiles = pkgs.writeShellApplication {
        name = "statix-files";
        text = ''
          flags=()
          while (($#)) && [[ $1 != -- ]]; do
            flags+=("$1")
            shift
          done
          shift
          status=0
          for file; do
            ${lib.getExe statix.package} check "''${flags[@]}" -- "$file" || status=1
          done
          exit "$status"
        '';
      };
    in
    {
      pre-commit.settings.hooks = {
        statix = {
          enable = lib.mkOverride 900 true;
          package = lib.mkOverride 900 pkgs.statix;
          entry = lib.mkOverride 900 (lib.getExe statixFiles);
          args = lib.mkOverride 900 [
            "--config"
            "${statixConfig}"
            "--format"
            "errfmt"
            "--"
          ];
          pass_filenames = lib.mkOverride 900 true;
        };
        deadnix = {
          enable = lib.mkOverride 900 true;
          package = lib.mkOverride 900 pkgs.deadnix;
          # With --fail, which the hook always passes.
          settings.noUnderscore = lib.mkOverride 900 true;
        };
      };
    };
}
