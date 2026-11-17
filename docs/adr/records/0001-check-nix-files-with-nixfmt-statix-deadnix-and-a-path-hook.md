---
id: ADR-0001
title: Check Nix files with nixfmt, statix, deadnix and a path hook
status: accepted
date: 2026-11-14
supersedes: []
superseded_by: []
related: []
affects:
  [
    "flake.nix",
    "flake.lock",
    "nix/**",
    "config/**",
    "scripts/**",
    "dev/**",
    "README.md",
  ]
review_by:
---

## Context

atom-nix is the atom of step 3 of [FY-0038][fy-0038] for Nix files: nixfmt as
the formatter, statix and deadnix as linters ([FY-0017][fy-0017]), and the hook
`flakeyard-nix-relative-paths` that [FY-0039][fy-0039] asks of it. Decisions of
flakeyard require of it:

- [FY-0017][fy-0017]: inputs are exactly the upstream flakes whose modules the
  atom imports, under canonical names, checked against the consumer's input of
  the same name before the import. Upstream options are set with
  `lib.mkOverride 900`, tool packages come from the consumer's `pkgs`, hook ids
  that upstream does not define start with `flakeyard-`, and the domain has one
  substitutable check, built with `lib.<system>.run` of git-hooks.nix from only
  the domain's hooks and the project's global excludes, over the project's
  source filtered coarsely by the hooks' `files`. Formatting is checked by
  `checks.treefmt`, which atom-workspace makes substitutable. Developer tools
  are `devShells.flakeyard-<atom>`; tests live in `dev/` and import the atom as
  consumers do.
- [FY-0037][fy-0037]: the atom ships flakeyard's configuration of each tool in
  `config/`; a project's file at the tool's standard root path replaces it
  wholly and is passed by flag as a store path of its own. nixfmt and deadnix
  have no configuration file. A stricter default ships first under
  `config/next/`.
- [FY-0039][fy-0039]: the root of a repository is defined once per flake, in
  `flake.nix` or `dev/flake.nix`, and in an atom in `nix/default.nix` as `./..`;
  every other Nix file reaches files outside its directory only as
  `root + "/<path>"`. atom-nix provides a hook that fails on a path that climbs
  out of its directory anywhere but in these entry files.
- [FY-0038][fy-0038]: releases start at `v0.1.0` with the moving tag `v0`; the
  warning of the next major version lives in `nix/next-major.nix`; scheduled
  tests run through workflow-check.

Experiments with nixfmt 1.5.0, statix `0-unstable-2026-05-14` and deadnix 1.3.2
of `nixos-26.05`, git-hooks.nix at `204b6977` and treefmt-nix at `0d6d739a`
showed:

- treefmt-nix defines `programs.nixfmt`, for `*.nix`, and its flake module sets
  `formatter` to the wrapper of treefmt with `lib.mkDefault`. git-hooks.nix
  defines the hooks `statix` and `deadnix`, both with `files = "\\.nix$"`.
- The hook `statix` runs `statix check` with `pass_filenames = false`, over the
  whole working directory. `statix check` takes one file or directory. It does
  not know pre-commit's excludes, and it applies the `ignore` of its
  configuration only while it walks a directory, not to a file it is given.
  `--config` with a file reads that file and nothing else.
- The configuration of statix has two keys, `disabled`, the names of the lints
  to switch off, and `ignore`, globs of paths to skip. Every lint not named is
  enabled; unknown names are ignored silently. `statix list` names 17 lints, W01
  to W23 with gaps. `bool_comparison` now reports only a comparison of two
  boolean literals.
- The hook `deadnix` always passes `--fail`, and its settings add flags such as
  `--no-underscore`.
- statix and deadnix with these flags report no findings in flakeyard's
  repositories, and every repository is formatted with nixfmt.
- A port of the lexer of Nix (`src/libexpr/lexer.l`) to a short Python script,
  with flex's longest match and its stack of states for strings, indented
  strings, paths and interpolations, found exactly the relative path literals
  that `nix-instantiate --parse` resolves in 415 files of the language tests of
  Nix and in 6150 files of nixpkgs and flakeyard (2742 paths, no difference). No
  repository of flakeyard has a path that climbs out of its directory outside
  its entry files.

## Decision

### Inputs and tools

The public flake has two inputs, `treefmt-nix` (numtide/treefmt-nix) and
`git-hooks` (cachix/git-hooks.nix). The atom fails evaluation with the line
`inputs.<name>.follows = "<name>";` when the consumer's input of the same name
has another store path, before it imports that module.

Amended for [FY-0040][fy-0040]: the public flake also declares `lib-atom`, which
the atom pins in its own `flake.lock` and consumers neither declare nor follow.
The check of `follows` and the warning of the next major version are the
functions `upstream` and `warning` of lib-atom, with the same messages; the atom
keeps no copy of them. The source of `checks.nix`, filtered by the hooks'
`files`, is the function `domain` of lib-atom 0.2.0, with the same files; the
atom keeps no copy of it.

The atom enables nixfmt in treefmt-nix and the hooks `statix`, `deadnix` and
`flakeyard-nix-relative-paths`, and owns them. All values are set with
`lib.mkOverride 900`, with packages of the consumer's `pkgs`:

- nixfmt: `treefmt.programs.nixfmt` with `pkgs.nixfmt` and no options. The atom
  has no formatting check of its own; `checks.treefmt` checks formatting.
- `statix`: the entry `statix-files`, which runs `statix check` with the
  arguments before `--` on each file after it; `pass_filenames = true`. The
  arguments are `--config` with the chosen file, `--format errfmt` and `--`.
  pre-commit selects the files, so its excludes apply.
- `deadnix`: `settings.noUnderscore = true`, so the entry is
  `deadnix --no-underscore --fail`.
- `flakeyard-nix-relative-paths`: the script `scripts/relative-paths.py` as a
  package of `pkgs.writers.writePython3Bin` of the consumer,
  `files = "\\.nix$"`. It fails on a relative path literal that climbs out of
  its directory at any segment, such as `../lib.nix` or `./a/../../b`, and names
  the file, line and column. In `flake.nix`, `dev/flake.nix` and
  `nix/default.nix`, paths from the root of the project, it accepts one root
  anchor: a climbing path of only `.` and `..` segments, such as `../.` or
  `./..`; a second one fails. Comments and the text of strings hold no paths;
  interpolations, also inside strings, do. An interpolation inside a path counts
  as one segment. Absolute, home (`~/`) and search (`<...>`) paths and URIs are
  not checked.

### Configuration

`config/statix.toml` holds flakeyard's configuration of statix: `disabled = []`
and `ignore = []`, with every lint of statix listed in a comment as enabled, so
that the file shows what runs and a new lint is noticed by a test. Files are
skipped with the excludes of git-hooks.nix, not with `ignore`.

The project's `statix.toml` at the root replaces the default. The atom detects
it with `builtins.pathExists` on the consumer's `self`, which for a git flake
holds only tracked files, and copies the chosen file with `builtins.path`.

deadnix is of the kind "flags only" without a file: its flags are fixed, and a
project changes them in the hook's settings. nixfmt has no configuration.

### Check and shell

`checks.nix` is built with `lib.<system>.run` of git-hooks.nix from only the
hooks `statix`, `deadnix` and `flakeyard-nix-relative-paths`, with every option
the project's configuration holds for them, the project's global
`pre-commit.settings.excludes` and the project's `pre-commit` and `git`
packages. Its `src` is the project's source filtered coarsely to the files that
the `files` pattern of one of the hooks matches, with only the directories that
hold them. pre-commit selects among them by `files`, `types` and `excludes`, as
the installed hook does.

`devShells.flakeyard-nix` holds nixfmt, statix, deadnix and the script of
`flakeyard-nix-relative-paths`, the packages of the treefmt program and the
hooks. No language server: it is no tool of a hook or of the formatter.

### Next major version

While `nix/next-major.nix` exists, `checks.nix` and `devShells.flakeyard-nix`
warn with `lib.warn` of the consumer's nixpkgs: the version, the end of support
6 months after it, and the link to the migration guide the file names
([FY-0016][fy-0016], [FY-0038][fy-0038]).

### Tests

`dev/flake.nix` imports the atom from the flake's own outputs called with the
dev flake's `treefmt-nix` and `git-hooks`, which is what `follows` gives a
consumer, together with atom-workspace, and checks this repository with it. As
amended for [FY-0040][fy-0040], the dev flake fetches the revision of lib-atom
that the root `flake.lock` pins, gives it to the atom and takes the fixture
projects and the tests of `follows` and the warning from its `internal/testing`,
with the messages restated in the tests. Its checks evaluate on x86_64-linux and
aarch64-linux: fixture projects that pass (with root anchors in entry files,
`../` in comments, strings and URLs, and unused bindings that start with `_`),
that fail every hook, that pass only with their own `statix.toml`, that a global
exclude makes pass and that other excludes leave failing; tests of the
configuration files, of the follows errors, of the next-major warning, of the
formatter with atom-workspace, that `config/statix.toml` lists every lint of
statix, and unit tests of the lexer on the edge cases of the lexical grammar of
Nix.

## Constraints

- The public flake MUST declare only the inputs `treefmt-nix`, `git-hooks` and
  `lib-atom` ([FY-0040][fy-0040]), and MUST fail evaluation with the exact
  follows line when the consumer's input of the same name has another store
  path.
- The atom MUST set nixfmt and the hooks `statix`, `deadnix` and
  `flakeyard-nix-relative-paths` only with `lib.mkOverride 900`, with packages
  of the consumer's `pkgs`.
- The atom MUST NOT add a formatting check; formatting is checked by
  `checks.treefmt`.
- The atom MUST pass the chosen `statix.toml` by `--config` to every run of
  statix, and MUST NOT let statix discover one.
- `config/statix.toml` MUST list every lint of the statix in the consumer's
  nixpkgs, and a test MUST check this against `statix list`.
- `checks.nix` MUST be built with `lib.<system>.run` of git-hooks.nix from only
  the three hooks and the project's global excludes, and the atom MUST NOT
  select its files beyond the coarse filter by the hooks' `files`.
- The lexer of `flakeyard-nix-relative-paths` MUST follow the lexical grammar of
  Nix, and its tests MUST cover comments, strings, indented strings,
  interpolations, URIs and interpolated paths.
- Everything listed in the "Public API" of the README is the public API
  ([FY-0017][fy-0017], [FY-0024][fy-0024]).

## Consequences

- (+) A project gets the same findings in the git hooks, in `nix flake check`
  and in CI, with flakeyard's configuration or its own `statix.toml`.
- (+) The rule of FY-0039 is checked by a tool instead of reviews.
- (+) A change outside Nix files keeps `checks.nix` cached.
- (+) New lints of statix are noticed by the scheduled tests.
- (−) The lexer is a second implementation of the lexical grammar of Nix; a
  change of the grammar needs a change of the script, which the tests catch only
  for the cases they hold.
- (−) statix runs once per file instead of once per run, which costs a process
  per file.
- (−) The `ignore` of a project's `statix.toml` has no effect; projects skip
  files with excludes.
- (−) `nix/default.nix` may hold a root anchor in every project, not only in
  atoms: the hook cannot tell an atom from another project.
- (±) A project file that is not tracked by git is seen by the tools in the
  working tree but not by the atom.

## Alternatives considered

- **The upstream entry of `statix`.** It checks the whole working directory and
  ignores pre-commit's excludes, so the check and the hook would select
  different files than the other hooks.
- **`statix check --stdin` per file.** Reports name `<stdin>` instead of the
  file.
- **A relative-path check with a regular expression or bash.** Cannot tell a
  path from the same text in comments, strings and indented strings, or find a
  path inside an interpolation.
- **tree-sitter-nix or nixf for the relative-path hook.** A full parser as a
  dependency of every consumer for one token class; the lexer is small and was
  checked against Nix itself.
- **`nix-instantiate --parse`.** Prints resolved absolute paths, so `./a/..` and
  `./.` cannot be told apart, and needs Nix inside the check.
- **A formatting check of the atom.** `checks.treefmt` already checks every
  formatter of the project ([FY-0017][fy-0017]).
- **nil in the shell.** A language server is no tool of a hook or of the
  formatter.

[fy-0016]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0016-pin-form.md
[fy-0017]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0017-atom-contract.md
[fy-0024]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0024-versioning-and-support.md
[fy-0037]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0037-atoms-ship-default-configs-that-projects-replace.md
[fy-0038]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0038-roll-out-the-atoms.md
[fy-0039]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0039-reach-repository-files-in-nix-from-one-root.md
[fy-0040]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0040-share-code-through-lib-repositories.md
