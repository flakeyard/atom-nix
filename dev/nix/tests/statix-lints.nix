# config/statix.toml enables every lint of the statix of the consumer's
# nixpkgs and lists each one in its comments: a new lint of statix, or a typo,
# fails.
{ facts, root, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings.hooks.statix) package;
      file = root + "/config/statix.toml";
      settings = builtins.fromTOML (builtins.readFile file);
    in
    {
      checks.test-statix-lints = pkgs.runCommand "test-statix-lints" { } ''
        # The settings: ${
          facts pkgs "test-statix-settings" {
            "no lint is disabled" = settings.disabled == [ ];
            "no path is ignored" = settings.ignore == [ ];
            "no other setting" =
              builtins.attrNames settings == [
                "disabled"
                "ignore"
              ];
          }
        }
        status=0
        while read -r code name; do
          if ! grep -q "^# $code $name: " ${file}; then
            echo "config/statix.toml does not list $code $name" >&2
            status=1
          fi
        done < <(${pkgs.lib.getExe package} list)
        listed=$(grep -c '^# W[0-9]* [a-z_]*: ' ${file})
        known=$(${pkgs.lib.getExe package} list | wc -l)
        if [[ $listed != "$known" ]]; then
          echo "config/statix.toml lists $listed lints; statix has $known" >&2
          status=1
        fi
        [[ $status == 0 ]] && touch $out
      '';
    };
}
