# atom-nix

A flake-parts module that formats Nix files with nixfmt and lints them with
statix, deadnix and the hook `flakeyard-nix-relative-paths`, as git hooks and as
the check `checks.nix` ([FY-0017][fy-0017], [ADR-0001][adr-0001]).

It checks every `*.nix` file:

- with nixfmt, through treefmt-nix: the formatting, in `nix fmt` and
  `checks.treefmt`;
- with statix: antipatterns, such as useless parentheses or a `let in` without
  bindings;
- with deadnix: unused bindings and function arguments;
- with `flakeyard-nix-relative-paths`: path literals that climb out of the
  directory of their file, which [FY-0039][fy-0039] replaces with
  `root + "/<path from the root>"`.

## Inputs

The atom has two inputs, `treefmt-nix` and `git-hooks`, which the project makes
it share with `follows` ([FY-0017][fy-0017]). While the atom is `0.y.z`, only
flakeyard's own repositories use it, in the form of [FY-0016][fy-0016]:

```nix
{
  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=<commit>&shallow=1";
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?ref=main&rev=<commit>&shallow=1";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks = {
      url = "git+https://github.com/cachix/git-hooks.nix?ref=master&rev=<commit>&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "git+https://github.com/numtide/treefmt-nix?ref=main&rev=<commit>&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    atom-nix = {
      url = "git+https://github.com/flakeyard/atom-nix?ref=v0&rev=<commit>&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workspace.url = "git+https://github.com/flakeyard/atom-workspace?ref=v0&rev=<commit>&shallow=1";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      imports = [
        inputs.atom-nix.flakeModules.default
        inputs.atom-workspace.flakeModules.default
      ];
    };
}
```

Without a `follows` line, evaluation fails with one of:

```text
atom-nix: input 'treefmt-nix' is locked twice; add to input atom-nix:
  inputs.treefmt-nix.follows = "treefmt-nix";
```

```text
atom-nix: input 'git-hooks' is locked twice; add to input atom-nix:
  inputs.git-hooks.follows = "git-hooks";
```

[atom-workspace][atom-workspace] joins the shell of the atom into
`devShells.default`, installs its hooks, enables the hook `treefmt`, makes
`checks.treefmt` substitutable and switches off the aggregated
`checks.pre-commit` of git-hooks.nix, which depends on the whole source of the
project ([FY-0038][fy-0038]).

## Files it reads

From the project's source, which for a git flake holds only tracked files:

- the Nix files, `*.nix` at any depth;
- `statix.toml` at the root, the configuration file of statix.

## Tools and configuration

Each tool gets the configuration the project chose: the project's file at the
tool's standard path at the root, else the default of the atom in
[`config/`](config). The project's file replaces the default wholly; nothing is
merged. The atom passes the chosen file by flag and never lets a tool discover
one ([FY-0037][fy-0037]).

| Tool    | Standard path | Default          | Project's file |
| ------- | ------------- | ---------------- | -------------- |
| nixfmt  | none          | none             | not read       |
| statix  | `statix.toml` | [config][statix] | replaces it    |
| deadnix | none          | flags            | not read       |

- nixfmt runs with its defaults: no width, indent or strict mode.
- statix always gets `--config` with the chosen file and `--format errfmt`, once
  for each file that pre-commit selects. [`config/statix.toml`][statix] enables
  every lint of statix and lists each one in a comment. statix applies the
  `ignore` of a configuration only while it walks a directory, so in the hook it
  has no effect; skip files with excludes.
- deadnix always gets `--fail` and `--no-underscore`: it reports unused bindings
  and arguments, except those whose names start with `_`.
- `flakeyard-nix-relative-paths` has no configuration.

To replace the default of statix, copy [`config/statix.toml`][statix] to
`statix.toml`, commit it and edit it. Since the atom reads only tracked files,
an untracked file is seen by the tool in the working tree but not by the atom.

## Relative paths

The hook `flakeyard-nix-relative-paths` fails on a relative path literal that
climbs out of the directory of its file at any segment, such as `../lib.nix`,
`./..` or `./a/../../b`, with the file, line and column:

```text
nix/hooks.nix:12:15: ../a.sh leaves its directory; use root + "/<path>" (FY-0039)
```

In the entry files `flake.nix`, `dev/flake.nix` and `nix/default.nix`, paths
from the root of the project, it accepts one root anchor: a climbing path of
only `.` and `..` segments, such as `../.` or `./..`. A second one fails:

```text
dev/flake.nix:5:13: ./.. is a second root anchor (FY-0039)
```

The hook lexes Nix as Nix does:

- comments and the text of strings and indented strings hold no paths;
  interpolations, also inside strings such as `"${../x}"`, hold code;
- an interpolation inside a path, such as `./${name}/..`, counts as one segment;
- absolute paths, `~/` paths, `<...>` paths and URIs, also `x:../y`, are not
  checked.

## Options

The atom adds no options. The hooks `statix`, `deadnix` and
`flakeyard-nix-relative-paths` and `treefmt.programs.nixfmt` are set with
`lib.mkOverride 900`, so a plain definition of the project, such as
`perSystem.pre-commit.settings.hooks.deadnix.settings.noUnderscore = false;`,
replaces a value of the atom without `mkForce`. The check runs the hooks'
`entry` and `args`, so such a definition changes it too. The check also honours
the hooks' other options and the project's global
`perSystem.pre-commit.settings.excludes`: pre-commit selects the files in the
check as the installed hook does.

## Outputs

- `flakeModules.default`: the module. It adds to every system:
  - the formatter `nixfmt` of treefmt-nix, enabled, with the package of the
    project's nixpkgs; treefmt-nix sets `formatter` to its wrapper of treefmt
    and adds `checks.treefmt`;
  - the hooks `statix`, `deadnix` and `flakeyard-nix-relative-paths`, enabled,
    with the packages of the project's nixpkgs;
  - `checks.nix`: the three hooks, run by pre-commit through `lib.<system>.run`
    of git-hooks.nix with the project's global excludes, over the files of the
    domain. It depends only on the files that the hooks' `files` patterns match
    and the chosen configuration file, so other changes keep it cached and
    substitutable;
  - `devShells.flakeyard-nix`: nixfmt, statix, deadnix and
    `flakeyard-nix-relative-paths`, which atom-workspace joins into
    `devShells.default`.

Supported systems are `x86_64-linux` and `aarch64-linux`.

## Supported upstream revisions

The oldest supported revisions are those the tests run with: treefmt-nix
`0d6d739a833ba9a9c93034862e4a7b061a062a1c`, git-hooks.nix
`204b6977e00caac19e2313015a598543ca7be150`, flake-parts
`ea2630b7470978622c7689a1ff75d2b389175399` and nixpkgs `nixos-26.05` at
`ac588ef1c914865dad517b337ea0eb9694a4021c`, with nixfmt 1.5.0, statix
`0-unstable-2026-05-14` and deadnix 1.3.2.

## Public API

Releases follow [semantic versioning][versioning] ([FY-0024][fy-0024]). The
public API is the inputs `treefmt-nix` and `git-hooks`, `flakeModules.default`,
the formatter `nixfmt`, the hooks `statix`, `deadnix` and
`flakeyard-nix-relative-paths`, the values the atom sets whose change fails a
project that passed before or rewrites its files (the default configuration, the
flags and the `files` of the hooks, the rule of `flakeyard-nix-relative-paths`
with its entry files), the files it reads, the outputs `checks.nix` and
`devShells.flakeyard-nix`, the supported systems and the oldest supported
upstream revisions. Versions of nixfmt, statix and deadnix come from the
project's nixpkgs and are not part of it.

The last minor release before a major one contains `nix/next-major.nix`; while
it exists, the check and the shell warn at evaluation that the next major
version is coming and where its migration guide is ([FY-0038][fy-0038]). A
stricter default configuration ships first as an opt-in under `config/next/`
([FY-0037][fy-0037]).

## Develop in the container

Open the repository in the flakeyard dev container: the editor reads
[`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json), and
`direnv` loads the shell of [`dev/flake.nix`](dev/flake.nix) through
[`.envrc`](.envrc) ([FY-0012][fy-0012]). [atom-workspace][atom-workspace] builds
the shell and installs the git hooks each time it starts. The container runs
`direnv allow` when it is created; run it once in every other worktree, and run
`direnv block` before you check out a branch you do not trust, since entering
the directory runs that branch's shell hook. Commit inside the container, whose
Nix store has the tools of the hooks. With Nix on the host, `direnv allow` or
`nix develop ./dev` gives the same shell.

The public [`flake.nix`](flake.nix) holds only the inputs and the module
([FY-0017][fy-0017]). [`dev/flake.nix`](dev/flake.nix), with its own lock,
imports the atom as consumers do, with atom-workspace, and holds the tests:

- `nix`, `treefmt`: the atom's checks of this repository;
- `test-good`, `test-bad`, `test-configs-project`: the check of the fixture
  projects in [`dev/fixtures`](dev/fixtures), which pass, fail every hook and
  pass only with their own `statix.toml`;
- `test-excluded`, `test-not-excluded`: the project's global excludes skip the
  failing files in the check, and other excludes do not;
- `test-configs`: the project's `statix.toml` replaces the default in the hook
  and in the check;
- `test-statix-lints`: [`config/statix.toml`][statix] enables and lists every
  lint of statix;
- `test-relative-paths`: the lexer of `flakeyard-nix-relative-paths` on the edge
  cases of the lexical grammar of Nix, in
  [`dev/tests/relative-paths.py`](dev/tests/relative-paths.py);
- `test-formatter`: nixfmt in treefmt and, with atom-workspace, the wrapper of
  treefmt as `formatter` and a substitutable `checks.treefmt`;
- `test-follows`: the errors for a missing `follows`;
- `test-next-major`: the warning of the next major version.

Run the same commands as CI:

```sh
nix flake check --no-update-lock-file ./dev
nix flake check --no-update-lock-file --no-build --all-systems ./dev
```

CI runs [`test.yaml`](.github/workflows/test.yaml), which calls
[workflow-check][workflow-check] with `./dev`: it checks `dev/flake.lock`,
builds every check on x86_64 and arm64 runners, checks the pull request title
and `renovate.json`, fails on configuration files of atom tools at their
standard root paths ([FY-0037][fy-0037]), and reports `check / required`
([FY-0034][fy-0034]). Its weekly run builds the checks against the current
branches of nixpkgs, git-hooks.nix, treefmt-nix and flake-parts instead of the
locked revisions ([FY-0038][fy-0038]).
[`scorecard.yaml`](.github/workflows/scorecard.yaml) runs OpenSSF Scorecard, and
[`release.yaml`](.github/workflows/release.yaml) releases the repository with
[workflow-release][workflow-release].

Before a pull request, also run actionlint, zizmor, prettier, markdownlint,
typos and `reuse lint`, and ruff on the Python scripts; the atoms that will
provide them are not adopted yet ([FY-0038][fy-0038]).

## License

[MIT](LICENSE).

[adr-0001]:
  docs/adr/records/0001-check-nix-files-with-nixfmt-statix-deadnix-and-a-path-hook.md
[atom-workspace]: https://github.com/flakeyard/atom-workspace
[statix]: config/statix.toml
[fy-0012]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0012-develop-in-container.md
[fy-0016]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0016-pin-form.md
[fy-0017]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0017-atom-contract.md
[fy-0024]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0024-versioning-and-support.md
[fy-0034]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0034-check-every-repository-with-workflow-check.md
[fy-0037]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0037-atoms-ship-default-configs-that-projects-replace.md
[fy-0038]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0038-roll-out-the-atoms.md
[fy-0039]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0039-reach-repository-files-in-nix-from-one-root.md
[versioning]: https://github.com/flakeyard/.github/blob/main/VERSIONING.md
[workflow-check]: https://github.com/flakeyard/workflow-check
[workflow-release]: https://github.com/flakeyard/workflow-release
