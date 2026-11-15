# The project's global excludes, pre-commit.settings.excludes, apply to the
# check as to the hooks: the failing files of dev/fixtures/bad pass once
# excluded, and still fail when the excludes name other files.
{ fixture, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      excluding =
        excludes:
        (fixture {
          name = "bad";
          module.perSystem.pre-commit.settings = { inherit excludes; };
        }).checks.${system}.nix;
      failure = pkgs.testers.testBuildFailure (excluding [ ''^nix/other\.nix$'' ]);
    in
    {
      checks.test-excluded = excluding [
        ''^nix/bad\.nix$''
        ''^dev/flake\.nix$''
      ];
      checks.test-not-excluded = pkgs.runCommand "test-not-excluded" { } ''
        log=${failure}/testBuildFailure.log
        cat "$log"
        grep -F 'nix/bad.nix>8:19:W:8:' "$log"
        grep -F 'Unused declarations were found.' "$log"
        grep -F 'nix/bad.nix:9:21: ../lib.nix leaves its directory' "$log"
        touch $out
      '';
    };
}
