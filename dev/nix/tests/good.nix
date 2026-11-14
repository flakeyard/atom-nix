# A project whose Nix files pass every hook: the check succeeds, with root
# anchors in its entry files, ../ in comments, strings and URLs, and unused
# bindings that start with _.
{ fixture, ... }:
{
  perSystem =
    { system, ... }:
    {
      checks.test-good = (fixture { name = "good"; }).checks.${system}.nix;
    };
}
