"""Read-only local context: versions, bounded Git changes, optional frozen mod diff."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")


def latest_release(root):
    """Match release.py's completed public code-release journal, not directory mtime."""
    candidates = []
    for directory in (root / "dist/releases").glob("*"):
        match = VERSION.fullmatch(directory.name)
        if not match:
            continue
        try:
            state = json.loads((directory / "state.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(state, dict):
            continue
        steps = state.get("steps", {})
        if not isinstance(steps, dict):
            continue
        if (state.get("version") == directory.name and state.get("audience") == "public"
                and state.get("release_kind") == "code"
                and all(steps.get(key) for key in
                        ("commit", "push", "github_draft", "steam", "pages", "github_release"))):
            candidates.append((tuple(map(int, match.groups())), directory))
    return max(candidates, default=(None, None))[1]


def normalize_scopes(root, scopes):
    result = []
    for scope in scopes:
        path = (root / scope).resolve()
        try:
            relative = path.relative_to(root.resolve()).as_posix()
        except ValueError:
            raise ValueError(f"Scope must stay inside the repository: {scope}") from None
        result.append(relative)
    return result


def matches_scope(path, scopes):
    return any(scope == "." or path == scope or path.startswith(scope + "/") for scope in scopes)


def git_changes(root):
    # -z preserves spaces, non-ASCII and embedded newlines; -uall counts every untracked file.
    proc = subprocess.run(["git", "--no-optional-locks", "-C", str(root), "status", "--porcelain=v1", "-z",
                           "--untracked-files=all"], capture_output=True, check=True)
    records = proc.stdout.decode("utf-8", errors="surrogateescape").split("\0")
    changes = []
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue
        change = {"status": record[:2], "path": record[3:]}
        if "R" in record[:2] or "C" in record[:2]:
            change["original_path"] = records[index]
            index += 1
        changes.append(change)
    return changes


def bounded(items, limit):
    return {"total": len(items), "items": items[:limit], "omitted": max(0, len(items) - limit)}


def tree_hashes(directory):
    if not directory.is_dir():
        raise ValueError(f"Mod content directory does not exist: {directory}")
    hashes = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Refusing symlink while hashing mod content: {path.relative_to(directory)}")
        if path.is_file():
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            hashes[path.relative_to(directory).as_posix()] = digest.hexdigest()
    return hashes


def release_diff(root, release, limit):
    boundary = "Current mod/ vs latest successful public release content/ only; SHA256; excludes docs/tools/site."
    if release is None or not (release / "content").is_dir():
        return {"available": False, "boundary": boundary,
                "reason": "No successful public release with frozen content available."}
    current, previous = tree_hashes(root / "mod"), tree_hashes(release / "content")
    return {"available": True, "baseline": release.name, "boundary": boundary,
            "added": bounded(sorted(current.keys() - previous.keys()), limit),
            "modified": bounded(sorted(p for p in current.keys() & previous.keys()
                                       if current[p] != previous[p]), limit),
            "deleted": bounded(sorted(previous.keys() - current.keys()), limit)}


def summarize(root=ROOT, scopes=(), limit=20, include_release_diff=False):
    scopes = normalize_scopes(root, scopes)
    text = (root / "mod/modinfo.lua").read_text(encoding="utf-8")
    match = re.search(r'^\s*version\s*=\s*[\'\"]([^\'\"]+)[\'\"]', text, re.MULTILINE)
    release = latest_release(root)
    changes = git_changes(root)
    relevant = [c for c in changes if not scopes or matches_scope(c["path"], scopes)
                or matches_scope(c.get("original_path", ""), scopes)]
    # Root files share one group; path details are available only through scoped changes.
    groups = sorted(Counter(c["path"].split("/")[0] if "/" in c["path"] else "."
                            for c in relevant).items())
    summary = {"current_version": match.group(1) if match else None,
               "latest_successful_release": release.name if release else None,
               "git": {"total": len(changes),
                       "untracked": sum(c["status"] == "??" for c in changes),
                       "by_top_level": dict(groups[:limit]),
                       "by_top_level_total": len(groups),
                       "by_top_level_omitted": max(0, len(groups) - limit),
                       "by_top_level_omitted_changes": sum(count for _, count in groups[limit:])}}
    if scopes:
        summary["git"]["scopes"] = scopes
        summary["git"]["changes"] = bounded(relevant, limit)
    if include_release_diff:
        summary["release_diff"] = release_diff(root, release, limit)
    return summary


def display(summary):
    print("Current mod version: " + json.dumps(summary['current_version'] or 'unknown', ensure_ascii=False))
    print("Latest successful public release: " + json.dumps(summary['latest_successful_release'] or 'none', ensure_ascii=False))
    git = summary["git"]
    print(f"Git changes: {git['total']} (untracked: {git['untracked']})")
    print(f"Top-level groups ('.' = root files): {git['by_top_level_total']} "
          f"(omitted groups: {git['by_top_level_omitted']}, "
          f"omitted changes: {git['by_top_level_omitted_changes']})")
    for name, count in git["by_top_level"].items():
        print(f"  {json.dumps(name, ensure_ascii=False)}: {count}")
    if "changes" in git:
        changes = git["changes"]
        print(f"Scoped changes: {changes['total']} (omitted: {changes['omitted']})")
        for change in changes["items"]:
            # JSON escaping keeps newlines/control characters from altering terminal output.
            label = json.dumps(change["path"], ensure_ascii=False)
            if "original_path" in change:
                label += " <- " + json.dumps(change["original_path"], ensure_ascii=False)
            print(f"  {change['status']} {label}")
    if "release_diff" in summary:
        diff = summary["release_diff"]
        print(diff["boundary"])
        if not diff["available"]:
            print(diff["reason"])
        else:
            for category in ("added", "modified", "deleted"):
                group = diff[category]
                print(f"{category}: {group['total']} (omitted: {group['omitted']})")
                for path in group["items"]:
                    print("  " + json.dumps(path, ensure_ascii=False))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", nargs="+", action="extend", default=[], metavar="PATH",
                        help="repository-relative files/directories; only show matching Git paths")
    parser.add_argument("--limit", type=int, default=20, help="maximum paths per output group (default: 20)")
    parser.add_argument("--release-diff", action="store_true", help="hash current mod against frozen release content")
    parser.add_argument("--json", action="store_true", help="emit bounded summary as JSON")
    args = parser.parse_args(argv)
    if args.limit < 0:
        parser.error("--limit must be nonnegative")
    try:
        summary = summarize(scopes=args.scope, limit=args.limit, include_release_diff=args.release_diff)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"context: {exc}\n")
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        display(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
