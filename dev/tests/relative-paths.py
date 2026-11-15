"""Unit tests of scripts/relative-paths.py, the lexer of the hook
flakeyard-nix-relative-paths, on the edge cases of Nix's lexical grammar.

Usage: relative-paths.py <path of scripts/relative-paths.py>
"""

import importlib.util
import sys
import unittest

spec = importlib.util.spec_from_file_location("hook", sys.argv.pop(1))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


def climbing(text):
    """The source of every path literal that climbs out of its directory."""
    return [source for _, source, value in hook.paths(text) if hook.climbs(value)]


class Climbing(unittest.TestCase):
    def test_parent(self):
        self.assertEqual(climbing("import ../lib.nix"), ["../lib.nix"])

    def test_anchors(self):
        self.assertEqual(climbing("[ ./.. ../. ../.. ]"), ["./..", "../.", "../.."])

    def test_own_directory(self):
        self.assertEqual(climbing("[ ./. ./a.nix ./a/b ./a/../b ]"), [])

    def test_climbing_after_descending(self):
        self.assertEqual(climbing("./a/../../b"), ["./a/../../b"])

    def test_without_dot(self):
        # a/b is a path in Nix, not a division.
        self.assertEqual(climbing("[ a/b a/../.. ]"), ["a/../.."])

    def test_division(self):
        self.assertEqual(climbing("x / 2 + y /2"), [])

    def test_absolute_home_and_search_paths(self):
        self.assertEqual(climbing("[ /a/../b ~/../b <nixpkgs/..> ]"), [])

    def test_interpolated_home_paths(self):
        # The closing brace ends the interpolation, not the attribute set.
        self.assertEqual(
            climbing("{ a = ~/${b}/../c; d = ~/e${f}; g = ../h; }"), ["../h"]
        )

    def test_trailing_slash_and_terminators(self):
        self.assertEqual(climbing("{ a = ../x; b = (../y); }"), ["../x", "../y"])

    def test_end_of_file(self):
        self.assertEqual(climbing("../x"), ["../x"])


class Comments(unittest.TestCase):
    def test_line_comment(self):
        self.assertEqual(climbing("# ../x\n1"), [])

    def test_block_comment(self):
        self.assertEqual(climbing("/* ../x\n ../y */ 1"), [])

    def test_doc_comment(self):
        self.assertEqual(climbing("/** ../x */ 1"), [])

    def test_hash_ends_a_path(self):
        self.assertEqual(climbing("./a#../x"), [])

    def test_comment_in_interpolation(self):
        self.assertEqual(climbing('"${ # ../x\n ../y }"'), ["../y"])


class Strings(unittest.TestCase):
    def test_text(self):
        self.assertEqual(climbing('"../x"'), [])

    def test_escaped_quote(self):
        self.assertEqual(climbing(r'"a\"../x"'), [])

    def test_interpolation(self):
        self.assertEqual(climbing('"${../x}"'), ["../x"])

    def test_escaped_interpolation(self):
        self.assertEqual(climbing(r'"\${../x}"'), [])

    def test_dollar_dollar(self):
        # $$ is two characters of text, so ${ after it is text too.
        self.assertEqual(climbing('"$${../x}"'), [])

    def test_dollar_at_end(self):
        self.assertEqual(climbing('"a$" + ../x'), ["../x"])

    def test_nested(self):
        self.assertEqual(climbing('"${"${../x}" + "../y"}"'), ["../x"])

    def test_braces_in_strings(self):
        self.assertEqual(climbing('{ a = "}"; b = ../x; c = "{"; }'), ["../x"])

    def test_attribute_set_in_interpolation(self):
        self.assertEqual(climbing('"${{ a = ../x; }.a}" + "../y"'), ["../x"])

    def test_dynamic_attribute(self):
        self.assertEqual(climbing("a.${../x} + ../y"), ["../x", "../y"])


class IndentedStrings(unittest.TestCase):
    def test_text(self):
        self.assertEqual(climbing("''\n  ../x\n  \"../y\"\n''"), [])

    def test_interpolation(self):
        self.assertEqual(climbing("''\n  ${../x}\n''"), ["../x"])

    def test_escaped_interpolation(self):
        self.assertEqual(climbing("'' ''${../x} ''"), [])

    def test_escaped_quotes(self):
        # ''' is two quotes of text; the string ends at the next ''.
        self.assertEqual(climbing("'' '''../x'' + ../y"), ["../y"])

    def test_escape(self):
        self.assertEqual(climbing("'' ''\\n ../x '' + ../y"), ["../y"])

    def test_single_quotes(self):
        self.assertEqual(climbing("'' it's '../x' ${../y} ''"), ["../y"])

    def test_dollar(self):
        self.assertEqual(climbing("'' $$ $'${../x} ''"), ["../x"])

    def test_identifier_with_quotes(self):
        # a'' is an identifier, not the start of a string.
        self.assertEqual(climbing("let a'' = 1; in ../x"), ["../x"])


class Uris(unittest.TestCase):
    def test_url(self):
        self.assertEqual(climbing("https://example.com/a/../../b"), [])

    def test_url_in_string(self):
        self.assertEqual(climbing('"git+https://example.com/../x?ref=main"'), [])

    def test_uri_without_space(self):
        # x:../y is a URI in Nix, not a function.
        self.assertEqual(climbing("x:../y"), [])

    def test_function(self):
        self.assertEqual(climbing("x: ../y"), ["../y"])


class InterpolatedPaths(unittest.TestCase):
    def test_parent_then_interpolation(self):
        self.assertEqual(climbing("../${name}"), ["../${name}"])

    def test_interpolation_first(self):
        self.assertEqual(climbing("./${name}/b"), [])

    def test_interpolation_then_parent(self):
        # An interpolation is one segment of unknown name.
        self.assertEqual(climbing("./${a}/.. ./${a}/../.."), ["./${a}/../.."])

    def test_inside_a_segment(self):
        self.assertEqual(climbing("./a-${b}/../c"), [])

    def test_path_in_path(self):
        self.assertEqual(climbing("./a/${toString ../x}/b"), ["../x"])


class Findings(unittest.TestCase):
    def test_position_and_message(self):
        self.assertEqual(
            hook.findings("nix/a.nix", "{\n  b = ../c;\n}\n"),
            [
                'nix/a.nix:2:7: ../c leaves its directory; use root + "/<path>" (FY-0039)'
            ],
        )

    def test_one_anchor_in_entry_files(self):
        for name in ["flake.nix", "dev/flake.nix", "nix/default.nix"]:
            self.assertEqual(hook.findings(name, "{ root = ../.; a = ./.; }"), [])

    def test_second_anchor(self):
        self.assertEqual(
            hook.findings("dev/flake.nix", "[ ../. ./.. ]"),
            ["dev/flake.nix:1:8: ./.. is a second root anchor (FY-0039)"],
        )

    def test_other_paths_in_entry_files(self):
        self.assertEqual(
            len(hook.findings("nix/default.nix", "[ ./.. ../lib.nix ]")), 1
        )

    def test_anchor_elsewhere(self):
        for name in ["nix/hooks.nix", "sub/flake.nix", "dev/nix/default.nix"]:
            self.assertEqual(len(hook.findings(name, "./..")), 1)

    def test_comments_only(self):
        self.assertEqual(hook.findings("a.nix", "# ../x\n/* ../y */ 1"), [])


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1], verbosity=2)
