#!/usr/bin/env python3
"""Detect the Fresh Eyes run marker in a review result.

The ONE home for the run marker, as fresheyes-verdict.py is the one home for the
verdict marker. Both fresheyes.sh (the launcher) and fresheyes-progress.sh (the
poller) call this file, so they can never disagree about which run a result
belongs to. Do not copy this regex elsewhere.

Usage: fresheyes-handle.py <result-file> <expected-handle>

Prints and exits:
  ok <handle>        0   the result carries this run's marker
  mismatch <handle>  6   it carries a DIFFERENT run's marker
  absent             1   it carries no marker
  error <why>        7   this script ran and could not READ the result

A usage error exits 2. Any other status means this script could not RUN at all
(no python3, the file missing from a partially-synced skill directory), which
the callers treat differently from `error`: a checker that cannot run must never
destroy a finished manual review, while a result that cannot be read has no text
to deliver in the first place. So this script never invents an exit code for a
condition it cannot observe.

The LAST marker in the file wins, the same rule fresheyes-verdict.py uses, and
for the same reason: a review OF fresheyes quotes marker lines, while a
compliant reviewer's own marker is the last line of its output.
"""

import json
import re
import sys

OK = 0
ABSENT = 1
USAGE = 2
MISMATCH = 6
UNREADABLE = 7

# Only the tail is scanned: the marker a reviewer is asked for is its last line,
# and a result can be large — the poller re-reads it every 30-60 seconds.
TAIL_BYTES = 64 * 1024
# A structured (automatic-mode) result is small; anything larger is not one.
JSON_MAX_BYTES = 1024 * 1024

# Bounded: the captured token is echoed into diagnostics and into status.json,
# and a replaying reviewer controls it. A handle is 22 characters.
MARKER_RE = re.compile(
    r"^[ \t]*FRESHEYES-RUN:[ \t]*([A-Za-z0-9][A-Za-z0-9._-]{0,127})[ \t]*$",
    re.MULTILINE,
)


def read_tail(path):
    with open(path, "rb") as handle:
        try:
            handle.seek(0, 2)
            size = handle.tell()
            if size > TAIL_BYTES:
                handle.seek(size - TAIL_BYTES)
            else:
                handle.seek(0)
        except OSError:
            # Not seekable (a pipe or device): read what there is.
            size = None
        data = handle.read(TAIL_BYTES + 1)
    return data.decode("utf-8", errors="replace"), size


def handle_from_json(path, size):
    """The run_handle of an automatic-mode result, or None."""
    if size is None or size > JSON_MAX_BYTES:
        return None
    try:
        with open(path, "rb") as handle:
            data = json.loads(handle.read().decode("utf-8", errors="replace"))
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    found = data.get("run_handle")
    if isinstance(found, str) and found.strip():
        return found.strip()
    return None


def main():
    if len(sys.argv) != 3:
        print("usage: fresheyes-handle.py <result-file> <expected-handle>", file=sys.stderr)
        return USAGE
    path, expected = sys.argv[1], sys.argv[2]
    if not expected:
        print("usage: fresheyes-handle.py <result-file> <expected-handle>", file=sys.stderr)
        return USAGE

    try:
        text, size = read_tail(path)
    except OSError as exc:
        print("error %s" % exc.__class__.__name__)
        return UNREADABLE

    found = handle_from_json(path, size)
    if found is None:
        matches = MARKER_RE.findall(text)
        found = matches[-1] if matches else None

    if found is None:
        print("absent")
        return ABSENT
    if found == expected:
        print("ok %s" % found)
        return OK
    print("mismatch %s" % found)
    return MISMATCH


if __name__ == "__main__":
    raise SystemExit(main())
