#!/usr/bin/env python3
"""Validate Conventional Commits subject lines read from stdin.

Input is one subject per line, optionally prefixed with a label and a tab:

    a1b2c3d4<TAB>feat(macos): detach the popover into a floating window

The label is only used to make the failure message point at something; it
defaults to "subject" when absent. Every offending line produces a GitHub
Actions error annotation, and the exit status is 1 if any line failed.

Used by .github/workflows/pr-conventions.yml for both the pull request title
and the subjects of the commits in a pull request. Kept as one script so the
two jobs cannot drift apart. Deliberately dependency-free: it runs on the
python3 that ships with the runner image, and works the same way locally:

    git log --format='%h%x09%s' origin/main..HEAD |
        python3 .github/scripts/check-conventional-subjects.py
"""

from __future__ import annotations

import re
import sys

# The types documented in CONTRIBUTING.md. Keep the two lists in step: a type
# accepted here but undocumented is a trap, and one documented but rejected
# here is worse.
TYPES = (
    "build",
    "chore",
    "ci",
    "docs",
    "feat",
    "fix",
    "perf",
    "refactor",
    "revert",
    "style",
    "test",
)

# type(optional-scope)!: description
#
# The scope is not constrained beyond "non-empty, no parentheses": scopes here
# are informal (macos, ios, editor, ...) and an allow-list would reject
# reasonable new ones. The "!" marks a breaking change. The single space after
# the colon is required by the spec.
SUBJECT = re.compile(
    r"^(?:" + "|".join(TYPES) + r")"  # type
    r"(?:\([^()]+\))?"  # optional scope
    r"!?"  # optional breaking-change marker
    r": "  # separator
    r"\S.*$"  # description, not just whitespace
)

# `git revert` writes `Revert "<subject of the reverted commit>"` by default.
# Rejecting that would mean the only way to land a revert is to rewrite a
# message git generated correctly, so accept it as-is.
GIT_REVERT = re.compile(r'^Revert ".+"$')

# CONTRIBUTING.md asks for subjects under about 72 characters. "About" is not
# something to fail a build over, so it is a warning.
SOFT_LENGTH_LIMIT = 72

HINT = (
    "Expected Conventional Commits: 'type: description', "
    "'type(scope): description' or 'type!: description', where type is one of "
    + ", ".join(TYPES)
    + ". See CONTRIBUTING.md."
)


def annotate(level: str, message: str) -> None:
    print(f"::{level}::{message}")


def check(label: str, subject: str) -> bool:
    """Return True if `subject` is acceptable, annotating either way."""
    if GIT_REVERT.match(subject):
        print(f"ok      {label}: {subject}  (git-generated revert)")
        return True

    if not SUBJECT.match(subject):
        annotate("error", f"{label}: {subject!r} is not a Conventional Commits subject. {HINT}")
        return False

    if len(subject) > SOFT_LENGTH_LIMIT:
        annotate(
            "warning",
            f"{label}: subject is {len(subject)} characters, over the "
            f"{SOFT_LENGTH_LIMIT}-character guideline in CONTRIBUTING.md.",
        )

    print(f"ok      {label}: {subject}")
    return True


def main() -> int:
    failures = 0
    checked = 0

    for line in sys.stdin.read().splitlines():
        label, tab, subject = line.partition("\t")
        if not tab:
            label, subject = "subject", label
        # Only the first line of a commit message is the subject; a body arriving
        # here would already have been split by splitlines(). Trailing
        # whitespace and a stray CR are not worth a failure, so drop them.
        subject = subject.rstrip().replace("\r", "")
        if not subject:
            continue
        checked += 1
        if not check(label, subject):
            failures += 1

    if checked == 0:
        annotate("error", "No subjects to check were read from stdin.")
        return 1

    if failures:
        annotate(
            "error",
            f"{failures} of {checked} subject(s) are not Conventional Commits.",
        )
        return 1

    print(f"All {checked} subject(s) are Conventional Commits.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
