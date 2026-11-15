# The fixture projects in dev/fixtures break the rules of the atom on
# purpose; the hooks of this repository skip them. treefmt formats them too.
{
  perSystem.pre-commit.settings.excludes = [ "^dev/fixtures/" ];
}
