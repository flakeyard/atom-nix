# A project whose Nix files fail every hook: the check fails and reports the
# findings of each.
{ fixture, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      failure = pkgs.testers.testBuildFailure (fixture { name = "bad"; }).checks.${system}.nix;
    in
    {
      checks.test-bad = pkgs.runCommand "test-bad" { } ''
        log=${failure}/testBuildFailure.log
        cat "$log"
        grep -F 'nix/bad.nix>8:19:W:8:' "$log"
        grep -F 'Unused declarations were found.' "$log"
        grep -F 'nix/bad.nix:9:21: ../lib.nix leaves its directory' "$log"
        grep -F 'dev/flake.nix:5:13: ./.. is a second root anchor' "$log"
        touch $out
      '';
    };
}
