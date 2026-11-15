# A finding of each hook: statix useless_parens, deadnix an unused binding,
# flakeyard-nix-relative-paths a path that climbs out of nix/.
{ x }:
let
  unused = 1;
in
{
  parenthesized = (x);
  imported = import ../lib.nix;
}
