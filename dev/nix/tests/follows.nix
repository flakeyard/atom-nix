# A consumer that locks treefmt-nix or git-hooks.nix a second time fails at
# evaluation with the follows line to add (FY-0017).
{ testing, ... }:
{
  perSystem = testing.follows {
    output = [
      "devShells"
      "flakeyard-nix"
    ];
    # Restated: the text is the interface (FY-0035).
    messages = {
      treefmt-nix = ''
        atom-nix: input 'treefmt-nix' is locked twice; add to input atom-nix:
          inputs.treefmt-nix.follows = "treefmt-nix";'';
      git-hooks = ''
        atom-nix: input 'git-hooks' is locked twice; add to input atom-nix:
          inputs.git-hooks.follows = "git-hooks";'';
    };
  };
}
