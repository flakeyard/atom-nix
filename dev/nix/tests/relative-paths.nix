# The lexer of the hook flakeyard-nix-relative-paths on the edge cases of the
# lexical grammar of Nix: comments, strings, indented strings,
# interpolations, URIs and interpolated paths.
{ root, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-relative-paths = pkgs.runCommand "test-relative-paths" { } ''
        ${pkgs.lib.getExe pkgs.python3} ${root + "/dev/tests/relative-paths.py"} \
          ${root + "/scripts/relative-paths.py"}
        touch $out
      '';
    };
}
