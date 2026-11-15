# The formatter: nixfmt of the consumer's nixpkgs in treefmt, and, with
# atom-workspace, the wrapper of treefmt as formatter and a substitutable
# checks.treefmt.
{
  facts,
  fixture,
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      project = fixture {
        name = "good";
        module.imports = [ inputs.atom-workspace.flakeModules.default ];
      };
      values = project.allSystems.${system};
    in
    {
      checks.test-formatter = facts pkgs "test-formatter" {
        "nixfmt is enabled" = values.treefmt.programs.nixfmt.enable;
        "nixfmt is the consumer's" = values.treefmt.programs.nixfmt.package == pkgs.nixfmt;
        "the formatter is the wrapper of treefmt" =
          project.formatter.${system}.drvPath == values.treefmt.build.wrapper.drvPath;
        "checks.treefmt is substitutable" = project.checks.${system}.treefmt.allowSubstitutes;
        "the hook treefmt is enabled" = values.pre-commit.settings.hooks.treefmt.enable;
      };
    };
}
