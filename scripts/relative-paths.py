"""The hook flakeyard-nix-relative-paths (FY-0039).

Fails on a path literal that climbs out of the directory of its Nix file,
such as ../lib.nix or ./a/../../b. The entry files flake.nix, dev/flake.nix
and nix/default.nix may hold one root anchor: a climbing path of only . and
.. segments, such as ../. or ./.. .

The lexer follows src/libexpr/lexer.l of Nix: the longest match wins, the
first rule on a tie, and a stack of states covers strings, indented strings,
paths and the interpolations inside them. Comments and the text of strings
hold no paths; an interpolation holds code, so "${../x}" holds one.

Usage: relative-paths.py FILE... with paths from the root of the project.
"""

import re
import sys

ENTRY_FILES = {"flake.nix", "dev/flake.nix", "nix/default.nix"}

PATH_CHAR = r"[a-zA-Z0-9._\-+]"
PATH = rf"{PATH_CHAR}*(?:/{PATH_CHAR}+)+/?"
PATH_SEG = rf"{PATH_CHAR}*/"

# The rules of the default state, in the order of lexer.l. Keywords are
# matched as identifiers, which have the same length; single characters
# fall to the last rule.
DEFAULT_RULES = [
    ("other", re.compile(r"\.\.\.|==|!=|<=|>=|&&|\|\||->|//|\+\+|<\||\|>")),
    ("other", re.compile(r"[a-zA-Z_][a-zA-Z0-9_'\-]*")),
    ("other", re.compile(r"[0-9]+")),
    (
        "other",
        re.compile(r"(?:(?:[1-9][0-9]*\.[0-9]*)|(?:0?\.[0-9]+))(?:[Ee][+-]?[0-9]+)?"),
    ),
    ("interpolation", re.compile(r"\$\{")),
    ("close", re.compile(r"\}")),
    ("open", re.compile(r"\{")),
    ("string", re.compile(r'"')),
    ("indented", re.compile(r"''(?: *\n)?")),
    ("path_start", re.compile(rf"{PATH_SEG}\$\{{")),
    ("path_start", re.compile(r"~/\$\{")),
    ("path", re.compile(PATH)),
    ("path", re.compile(rf"~(?:/{PATH_CHAR}+)+/?")),
    ("other", re.compile(rf"<{PATH_CHAR}+(?:/{PATH_CHAR}+)*>")),
    ("other", re.compile(r"[a-zA-Z][a-zA-Z0-9+\-.]*:[a-zA-Z0-9%/?:@&=+$,\-_.!~*']+")),
    ("other", re.compile(r"/\*\*[^/*](?:[^*]|\*+[^*/])*\*+/")),
    ("other", re.compile(r"[ \t\r\n]+")),
    ("other", re.compile(r"#[^\r\n]*")),
    ("other", re.compile(r"/\*(?:[^*]|\*+[^*/])*\*+/")),
    ("other", re.compile(r"[\s\S]")),
]

STRING_CHARS = r'(?:[^$"\\]|\$[^{"\\]|\\[\s\S]|\$\\[\s\S])'
STRING_RULES = [
    ("other", re.compile(rf"{STRING_CHARS}*\$(?=\")")),
    ("other", re.compile(rf"{STRING_CHARS}+")),
    ("interpolation", re.compile(r"\$\{")),
    ("end", re.compile(r'"')),
    ("other", re.compile(r"\$\\|\$|\\")),
]

INDENTED_RULES = [
    ("other", re.compile(r"(?:[^$']|\$[^{']|'[^'$])+")),
    ("other", re.compile(r"''\$|\$")),
    ("other", re.compile(r"'''")),
    ("other", re.compile(r"''\\[\s\S]")),
    ("interpolation", re.compile(r"\$\{")),
    ("end", re.compile(r"''")),
    ("other", re.compile(r"'")),
]

PATH_RULES = [
    ("interpolation", re.compile(r"\$\{")),
    ("piece", re.compile(rf"{PATH}|{PATH_SEG}|{PATH_CHAR}+")),
]

RULES = {
    "default": DEFAULT_RULES,
    "string": STRING_RULES,
    "indented": INDENTED_RULES,
    "path": PATH_RULES,
}

# The stand-in for an interpolation inside a path: one unknown segment.
UNKNOWN = "\0"


def match(rules, text, pos):
    """The kind and end of the longest match; the first rule on a tie."""
    best = None
    for kind, rule in rules:
        found = rule.match(text, pos)
        if found and found.end() > pos and (best is None or found.end() > best[1]):
            best = (kind, found.end())
    return best


def paths(text):
    """Every relative path literal: (offset, source, segments)."""
    found = []
    # Frames of [state, path]; path is [offset, pieces] in the state path.
    stack = [["default", None]]
    pos = 0
    while pos < len(text):
        frame = stack[-1]
        state = frame[0]
        best = match(RULES[state], text, pos)
        if best is None:
            if state != "path":
                # Unterminated input; the parser of Nix fails on it.
                break
            # The end of a path: the character is lexed again in the state
            # below.
            offset, pieces = frame[1]
            found.append((offset, text[offset:pos], "".join(pieces)))
            stack.pop()
            continue
        kind, end = best
        token = text[pos:end]
        if state == "path":
            if kind == "interpolation":
                frame[1][1].append(UNKNOWN)
                stack.append(["default", None])
            else:
                frame[1][1].append(token)
        elif kind in ("interpolation", "open"):
            stack.append(["default", None])
        elif kind == "close":
            if len(stack) > 1:
                stack.pop()
        elif kind == "string":
            stack.append(["string", None])
        elif kind == "indented":
            stack.append(["indented", None])
        elif kind == "end":
            stack.pop()
        elif kind == "path":
            stack.append(["path", [pos, [token]]])
        elif kind == "path_start":
            # Lexed again: the first segment, then the interpolation.
            end = text.index("/", pos) + 1
            stack.append(["path", [pos, [text[pos:end]]]])
        pos = end
    for frame in reversed(stack):
        if frame[0] == "path":
            offset, pieces = frame[1]
            found.append((offset, text[offset:], "".join(pieces)))
    return sorted(
        (offset, source, value)
        for offset, source, value in found
        if not value.startswith(("/", "~"))
    )


def climbs(value):
    """Whether a relative path leaves its directory at any segment."""
    depth = 0
    for segment in value.split("/"):
        if segment in ("", "."):
            continue
        depth += -1 if segment == ".." else 1
        if depth < 0:
            return True
    return False


def anchor(value):
    """Whether a path names only an ancestor directory, such as ../. ."""
    return all(segment in ("", ".", "..") for segment in value.split("/"))


def findings(name, text):
    """The messages for one file, with its path from the root."""
    messages = []
    anchors = 0
    for offset, source, value in paths(text):
        if not climbs(value):
            continue
        line = text.count("\n", 0, offset) + 1
        column = offset - (text.rfind("\n", 0, offset) + 1) + 1
        where = f"{name}:{line}:{column}"
        if name in ENTRY_FILES and anchor(value):
            anchors += 1
            if anchors > 1:
                messages.append(f"{where}: {source} is a second root anchor (FY-0039)")
            continue
        messages.append(
            f'{where}: {source} leaves its directory; use root + "/<path>" (FY-0039)'
        )
    return messages


def main(names):
    status = 0
    for name in names:
        with open(name, encoding="utf-8") as file:
            text = file.read()
        for message in findings(name.removeprefix("./"), text):
            print(message)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
