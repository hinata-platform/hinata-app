#!/usr/bin/env python3
"""Generate semantic, user-facing store release notes from the git commits since
the last release, and write them into every native platform's Fastlane changelog
for the given Android versionCode.

    tool/gen_changelog.py <versionCode> [--since <ref>] [--version X.Y.Z] [--write]

Writes (when --write):
  android/fastlane/metadata/android/{en-US,de-DE}/changelogs/<versionCode>.txt
  ios/fastlane/metadata/{en-US,de-DE}/release_notes.txt
  macos/fastlane/metadata/{en-US,de-DE}/release_notes.txt

"Semantic" notes:
  * If ANTHROPIC_API_KEY is set, Claude turns the commit list into clean, friendly,
    bilingual (EN + DE) "What's New" copy — grouped, no ticket IDs / jargon.
  * Otherwise a deterministic fallback groups by Conventional-Commit type.

Kept under Google Play's 500-char changelog limit (Apple allows 4000, so the same
concise copy is reused everywhere for consistency).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAY_LIMIT = 480  # keep a margin under Play's 500

# Commit subjects that never belong in user-facing notes.
_SKIP = re.compile(r"^(release|chore|ci|build|docs|doc|test|tests|style|refactor|"
                   r"merge|bump|wip)\b", re.I)
_TICKET = re.compile(r"^\s*\[?[A-Z][A-Z0-9]+-\d+\]?[:\-\s]*", re.I)
_CONV = re.compile(r"^(feat|fix|perf|improvement|improve|add|update)"
                   r"(\([^)]*\))?!?:\s*", re.I)


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()


def commits_since(since: str | None) -> list[str]:
    if not since:
        since = sh("git describe --tags --abbrev=0 2>/dev/null")
    rng = f"{since}..HEAD" if since else "HEAD"
    raw = sh(f"git log {rng} --no-merges --pretty=%s")
    out = []
    for line in raw.splitlines():
        s = line.strip()
        if not s or _SKIP.match(s):
            continue
        s = _TICKET.sub("", s)
        s = _CONV.sub("", s).strip()
        if s:
            out.append(s[0].upper() + s[1:])
    # de-dupe preserving order
    seen, uniq = set(), []
    for s in out:
        if s.lower() not in seen:
            seen.add(s.lower())
            uniq.append(s)
    return uniq


def _classify(subjects_raw: list[str]) -> dict[str, list[str]]:
    groups = {"new": [], "improved": [], "fixed": []}
    for s in subjects_raw:
        low = s.lower()
        if _match(low, ("feat", "add")):
            groups["new"].append(_clean(s))
        elif _match(low, ("fix", "bug")):
            groups["fixed"].append(_clean(s))
        else:
            groups["improved"].append(_clean(s))
    return groups


def _match(low, prefixes):
    return any(low.startswith(p) for p in prefixes)


def _clean(s):
    s = _CONV.sub("", _TICKET.sub("", s)).strip()
    return (s[0].upper() + s[1:]) if s else s


def llm_notes(subjects: list[str]) -> dict | None:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key or not subjects:
        return None
    model = os.environ.get("CHANGELOG_MODEL", "claude-sonnet-5")
    prompt = (
        "You write 'What's New' release notes for Hinata, an open-source, "
        "self-hosted project & issue-tracking app (boards, sprints, Gantt, "
        "reports, wiki, comments).\n\nTurn these commit messages since the last "
        "release into concise, friendly, USER-FACING notes. Group into a few "
        "bullet points (• ) — new features, then improvements, then fixes. Drop "
        "internal-only/dev/CI churn, ticket IDs, and jargon. No headings, no "
        "markdown bold. Keep EACH language under 440 characters total.\n\n"
        "Return STRICT JSON only: {\"en\": \"...\", \"de\": \"...\"} — English (US) "
        "and German (Deutschland, du-Form). Commits:\n- " + "\n- ".join(subjects)
    )
    body = json.dumps({
        "model": model,
        "max_tokens": 700,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={"x-api-key": key, "anthropic-version": "2023-06-01",
                 "content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.load(r)
        text = "".join(b.get("text", "") for b in data.get("content", []))
        text = re.search(r"\{.*\}", text, re.S).group(0)
        notes = json.loads(text)
        if notes.get("en") and notes.get("de"):
            return {"en": notes["en"].strip(), "de": notes["de"].strip()}
    except Exception as e:
        print(f"  (LLM changelog failed, using fallback: {e})", file=sys.stderr)
    return None


def fallback_notes(subjects: list[str]) -> dict:
    g = _classify(subjects)
    def build(new_h, imp_h, fix_h):
        lines = []
        for head, items in ((new_h, g["new"]), (imp_h, g["improved"]),
                            (fix_h, g["fixed"])):
            for it in items:
                lines.append(f"• {it}")
        return "\n".join(lines)
    en = build("New", "Improved", "Fixed") or "• Improvements and bug fixes."
    # Minimal German fallback (no MT available): a generic, honest note.
    de = ("• Neue Funktionen, Verbesserungen und Fehlerbehebungen."
          if any(g.values()) else "• Verbesserungen und Fehlerbehebungen.")
    return {"en": _fit(en), "de": _fit(de)}


def _fit(text: str) -> str:
    if len(text) <= PLAY_LIMIT:
        return text
    cut = text[:PLAY_LIMIT]
    return cut[:cut.rfind("\n")].rstrip() if "\n" in cut else cut.rstrip()


def write_all(code: int, notes: dict):
    files = []
    for lang, loc in (("en", "en-US"), ("de", "de-DE")):
        txt = _fit(notes[lang])
        files += [
            (f"android/fastlane/metadata/android/{loc}/changelogs/{code}.txt", txt),
            (f"ios/fastlane/metadata/{loc}/release_notes.txt", txt),
            (f"macos/fastlane/metadata/{loc}/release_notes.txt", txt),
        ]
    for rel, txt in files:
        p = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            f.write(txt + "\n")
        print("  wrote", rel)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("versionCode", type=int)
    ap.add_argument("--since", default=None)
    ap.add_argument("--version", default=None)
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    subjects = commits_since(a.since)
    print(f"commits since {a.since or 'last tag'}: {len(subjects)}")
    notes = llm_notes(subjects) or fallback_notes(subjects)
    print("--- EN ---\n" + notes["en"] + "\n--- DE ---\n" + notes["de"])
    if a.write:
        write_all(a.versionCode, notes)
    else:
        print("(dry run — pass --write to update the fastlane changelog files)")


if __name__ == "__main__":
    main()
