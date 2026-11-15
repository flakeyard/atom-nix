# A consumer that locks treefmt-nix or git-hooks.nix a second time fails at
# evaluation with the follows line to add (FY-0017).
{
  facts,
  fixture,
  inputs,
  root,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      # An input under another store path, as the atom's own lock gives it
      # without follows.
      other =
        input:
        input
        // {
          outPath = "/nix/store/00000000000000000000000000000000-source";
        };
      message =
        name:
        import (root + "/nix/follows.nix") {
          inherit name;
          atom = other inputs.${name};
          consumer = inputs.${name};
        };
      evaluated =
        atomInputs:
        builtins.tryEval
          (fixture (atomInputs // { name = "good"; })).devShells.${system}.flakeyard-nix.drvPath;
    in
    {
      checks.test-follows = facts pkgs "test-follows" {
        "the same inputs evaluate" = (evaluated { }).success;
        "another treefmt-nix fails" = !(evaluated { treefmt-nix = other inputs.treefmt-nix; }).success;
        "another git-hooks fails" = !(evaluated { git-hooks = other inputs.git-hooks; }).success;
        # Restated: the text is the interface (FY-0035).
        "the error names the follows line of treefmt-nix" =
          message "treefmt-nix" == ''
            atom-nix: input 'treefmt-nix' is locked twice; add to input atom-nix:
              inputs.treefmt-nix.follows = "treefmt-nix";'';
        "the error names the follows line of git-hooks" =
          message "git-hooks" == ''
            atom-nix: input 'git-hooks' is locked twice; add to input atom-nix:
              inputs.git-hooks.follows = "git-hooks";'';
      };
    };
}
