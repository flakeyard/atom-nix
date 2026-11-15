# The root module of atom-nix (FY-0017). It fails when the consumer locks
# treefmt-nix or git-hooks.nix a second time, imports the modules of both and
# the atom's modules. The atom's inputs reach the other files only as function
# arguments.
atomInputs:
{ inputs, ... }:
let
  # The module of an upstream flake, or the error that names the missing
  # follows line.
  upstream =
    name: module:
    let
      message = import ./follows.nix {
        inherit name;
        atom = atomInputs.${name};
        consumer = inputs.${name} or null;
      };
    in
    if message == null then module else throw message;
in
{
  key = toString ./default.nix;
  _file = ./default.nix;
  imports = [
    (upstream "treefmt-nix" atomInputs.treefmt-nix.flakeModule)
    (upstream "git-hooks" atomInputs.git-hooks.flakeModule)
    ./treefmt.nix
    ./shell.nix
  ];
}
