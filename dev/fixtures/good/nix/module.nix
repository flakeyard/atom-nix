# Paths from the root, and ../ only where it is no path: in comments such as
# this one, in strings and in URLs. Bindings that start with _ may be unused.
{ root, lib }:
let
  _unused = 1;
in
{
  # A block comment: ../a.nix
  script = root + "/scripts/a.sh";
  text = "../b.nix";
  indented = ''
    ../c.nix ''${../d.nix}
  '';
  url = "https://example.com/a/../b";
  own = ./a/../b.nix;
  enabled = lib.id true;
}
