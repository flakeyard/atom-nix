# The configuration file of statix (FY-0037): the project's statix.toml
# replaces the default of the atom, and the chosen file is an input of the
# check as a store path of its own.
{
  facts,
  fixture,
  root,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      project = name: (fixture { inherit name; }).allSystems.${system};
      # The store path of a file, as text to look for.
      stored =
        path:
        builtins.unsafeDiscardStringContext "${builtins.path {
          inherit path;
          name = baseNameOf path;
        }}";
      # The arguments of the hook and the configuration of pre-commit in the
      # check.
      uses =
        name: path:
        let
          inherit (project name) checks pre-commit;
        in
        lib.elem (stored path) pre-commit.settings.hooks.statix.args
        && lib.hasInfix (stored path) (builtins.toJSON checks.nix.config.rawConfig);
      own = root + "/dev/fixtures/project-config/statix.toml";
      default = root + "/config/statix.toml";
    in
    {
      checks.test-configs = facts pkgs "test-configs" {
        "the project's statix.toml is used" = uses "project-config" own;
        "the default statix.toml is not used" = !uses "project-config" default;
        "without a file, the default statix.toml is used" = uses "good" default;
      };
      # The Nix files of the project pass only with the project's file.
      checks.test-configs-project = (project "project-config").checks.nix;
    };
}
