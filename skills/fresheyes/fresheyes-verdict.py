#!/usr/bin/env python3
"""Detect the final review verdict in a Fresh Eyes review file.

The ONE home for the verdict marker. Both fresheyes.sh (the launcher) and
fresheyes-progress.sh (the poller) call this file, so they can never disagree
about what a completed review looks like. Do not copy this regex elsewhere.

Usage: fresheyes-verdict.py <review-file> [<run-handle>]
Prints "passed" or "failed" and exits 0.
Exits 1 when the file is missing/unreadable or carries no verdict of its own.

A review quotes what it reads, so the marker phrase anywhere in the file is not
a verdict (upstream #5, #13). Two rules decide which line is:

- The marker is a whole line of its own, flush left, plain, in bold or as a
  heading. An indented, line-numbered, blockquoted or inline copy is a quote.
- With a run handle, the verdict is bound to the run: the last FRESHEYES-RUN
  line in the file must carry this handle, and the line just above it (blank
  lines aside) must be the marker. A quoted pair carries another run's handle,
  and a run's handle is unknown before the run starts, so no file can carry it.
  Without a handle (a record from before the run marker existed) the last
  flush-left marker wins.

The run marker itself is read by fresheyes-handle.py, its one home.

Usage: fresheyes-verdict.py --no-files-examined <review-file>
Exits 0 when the review's "Files Examined" section is present and lists no
file: the reviewer says it read nothing, so the text is not a review whatever
its verdict says. The section lists no file when its first line says so
("None.", "- n/a", ...), whatever bullets explain it below, or when it has no
list entry other than such a line. Exits 1 otherwise, including when the file
is unreadable or has no such section. The FIRST such heading is the review's
own; the prompt puts it first, and a later one is a quotation.
"""

import importlib.util
import re
import sys
from pathlib import Path

VERDICT_RE = re.compile(
    r"^(?:#{1,6}[ \t]+)?(?:\*\*|__)?INDEPENDENT CODE REVIEW[ \t]+(PASSED|FAILED)\b"
    r"[ \t]*(?:\*\*|__)?[ \t]*$",
    re.IGNORECASE,
)

FILES_HEADING = re.compile(r"^\s*#{1,6}\s*files\s+examined\s*:?\s*$", re.IGNORECASE)
SECTION_END = re.compile(r"^\s*(#{1,6}\s|-{3,}\s*$|\*{3,}\s*$|_{3,}\s*$)")
LIST_ENTRY = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(.*\S)")
# A sentence that says no file was read may go on to say why. A short word
# ("None", "n/a", "nothing", "no files") must stand alone: then punctuation
# and a space or the end of the line, the end of the line, or a parenthesis or
# dash, with emphasis markup allowed around it. "None.", "**None.**",
# "None (reads failed)" and "No files were examined because ..." match; a file
# named none.py and prose like "None of these were modified" do not.
NO_FILE = re.compile(
    r"^[\s*_`]*(?:"
    r"(?:no\s+files?|nothing)\s+(?:(?:was|were)\s+)?(?:examined|read)\b"
    r"|"
    r"(?:none|n/?a|nothing|no\s+files?)[*_`]*"
    r"(?:[.:;,!][*_`]*(?=\s|$)|\s*$|\s+[(\u2014\u2013-])"
    r")",
    re.IGNORECASE,
)


def read(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def load_marker_re():
    path = Path(__file__).resolve().with_name("fresheyes-handle.py")
    spec = importlib.util.spec_from_file_location("fresheyes_handle", path)
    module = importlib.util.module_from_spec(spec)
    # The poller promises to write nothing; no __pycache__ beside the skill.
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module.MARKER_RE


def verdict_of(line):
    match = VERDICT_RE.match(line)
    return match.group(1).lower() if match else ""


def bound_verdict(lines, handle):
    marker_re = load_marker_re()
    for index in range(len(lines) - 1, -1, -1):
        found = marker_re.match(lines[index])
        if not found:
            continue
        if found.group(1) != handle:
            return ""
        for above in range(index - 1, -1, -1):
            if lines[above].strip():
                return verdict_of(lines[above])
        return ""
    return ""


def verdict(text: str, handle: str = "") -> str:
    lines = text.splitlines()
    if handle:
        return bound_verdict(lines, handle)
    found = ""
    for line in lines:
        found = verdict_of(line) or found
    return found


def examined_no_files(text: str) -> bool:
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if FILES_HEADING.match(line)), None)
    if start is None:
        return False
    first = True
    for line in lines[start + 1:]:
        if SECTION_END.match(line):
            break
        if not line.strip():
            continue
        entry = LIST_ENTRY.match(line)
        content = entry.group(1) if entry else line
        if first and NO_FILE.match(content):
            return True
        first = False
        if entry and not NO_FILE.match(content):
            return False
    return True


def main() -> int:
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--no-files-examined":
        text = read(args[1])
        return 0 if text is not None and examined_no_files(text) else 1
    if len(args) not in (1, 2):
        return 1
    text = read(args[0])
    if text is None:
        return 1
    found = verdict(text, args[1] if len(args) == 2 else "")
    if not found:
        return 1
    print(found)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
