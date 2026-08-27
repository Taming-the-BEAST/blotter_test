#!/usr/bin/env python3
"""Open one PR per tutorial repo migrating its README frontmatter to the new schema.

Values are copied verbatim from tutorials_metadata.yml; nothing is guessed.
Dry-run by default -- prints a diff per repo and opens nothing.

    uv run --with pyyaml _scripts/propose_metadata_prs.py [--only owner/repo]
    uv run --with pyyaml _scripts/propose_metadata_prs.py --push
"""
import argparse
import os
import re
import subprocess
import sys

import yaml

BRANCH = "tutorial-metadata-migration"

# Fields tutorials_metadata.yml may supply, mirroring FALLBACK_FIELDS in
# _scripts/generate-tutorial-data.rb.
FIELDS = ["beastversion_tutorial", "workflow", "status",
          "keywords", "packages", "domains", "beastversion_package"]

TITLE = "Migrate README frontmatter to the new tutorial metadata schema"

BODY = """\
Updates this tutorial's README frontmatter to the schema at
https://github.com/taming-the-beast/taming-the-beast.github.io/blob/master/tutorials/tutorial_schema.yml

- renames `beastversion` -> `beastversion_tutorial`, `tutorial_type` -> `workflow`
- removes the unused `level` field
- adds `workflow`, `status`, `keywords`, `packages`, `domains`

The values come from the central `tutorials_metadata.yml` on the Taming the BEAST
website, where they are currently maintained as a fallback. Moving them here makes
this repo the source of truth again and lets the tutorial appear correctly in the
filters on https://taming-the-beast.org/tutorials/.

Please correct anything that looks wrong -- the metadata was reviewed centrally,
not by the tutorial authors.
"""


def run(*args, **kwargs):
    """Run a command, echoing it first so the transcript documents what happened."""
    print("  $", " ".join(args), flush=True)
    return subprocess.run(args, check=True, text=True, **kwargs)


def read_repo_list(config_path):
    return yaml.safe_load(open(config_path))["tutorials"]


def read_metadata(metadata_path):
    # Lowercased keys: _config.yml and tutorials_metadata.yml disagree on the
    # casing of taming-the-BEAST/Mascot-Tutorial.
    data = yaml.safe_load(open(metadata_path))
    return {repo.lower(): entry for repo, entry in data.items()}


def rewrite_frontmatter(text, entry):
    """Return the README with migrated frontmatter, or None if it has none.

    Note: YAML comments in the frontmatter are dropped and quoting may be
    normalised -- both show up in the dry-run diff.
    """
    # [ \t]* rather than \s* on the closing delimiter, so blank lines that
    # follow the frontmatter stay in the body instead of being swallowed.
    match = re.match(r"\A---[ \t]*\n(.*?)\n---[ \t]*\n", text, re.DOTALL)
    if not match:
        return None
    front = yaml.safe_load(match.group(1)) or {}
    body = text[match.end():]

    front.setdefault("beastversion_tutorial", front.pop("beastversion", None))
    front.setdefault("workflow", front.pop("tutorial_type", None))
    front.pop("level", None)
    front.update({k: v for k, v in entry.items() if k in FIELDS})
    front = {k: v for k, v in front.items() if v is not None}

    # width=inf: never fold long values like `subtitle` onto a second line.
    dumped = yaml.dump(front, sort_keys=False, allow_unicode=True,
                       default_flow_style=False, width=float("inf"))
    return "---\n" + dumped + "---\n" + body


def process(repo, entry, workdir, push, login):
    name = repo.split("/")[1]
    path = os.path.join(workdir, name)
    print(f"\n=== {repo}", flush=True)

    if not os.path.isdir(path):
        run("gh", "repo", "clone", repo, path, "--", "--depth", "1")

    readme = os.path.join(path, "README.md")
    original = open(readme, encoding="utf-8").read()
    updated = rewrite_frontmatter(original, entry)

    if updated is None:
        print("  ! no parseable frontmatter - skipped")
        return
    if updated == original:
        print("  = already migrated - skipped")
        return

    open(readme, "w", encoding="utf-8").write(updated)
    run("git", "-C", path, "--no-pager", "diff", "--", "README.md")

    if not push:
        return

    run("gh", "repo", "fork", repo, "--clone=false")
    run("git", "-C", path, "checkout", "-b", BRANCH)
    run("git", "-C", path, "commit", "-am", TITLE)
    run("git", "-C", path, "push", "-u",
        f"https://github.com/{login}/{name}.git", BRANCH)
    run("gh", "pr", "create", "--repo", repo, "--head", f"{login}:{BRANCH}",
        "--title", TITLE, "--body", BODY)


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--push", action="store_true",
                        help="fork, push a branch and open the PR (default: diff only)")
    parser.add_argument("--only", metavar="OWNER/REPO", help="process a single repo")
    parser.add_argument("--limit", type=int, help="process at most N repos")
    parser.add_argument("--workdir", default="/tmp/ttb-metadata-prs",
                        help="where clones are kept (reused across runs)")
    args = parser.parse_args()

    repos = read_repo_list(os.path.join(here, "_config.yml"))
    metadata = read_metadata(os.path.join(here, "tutorials_metadata.yml"))

    if args.only:
        repos = [r for r in repos if r.lower() == args.only.lower()]
        if not repos:
            sys.exit(f"{args.only} is not in the _config.yml tutorials list")
    if args.limit:
        repos = repos[:args.limit]

    login = None
    if args.push:
        login = run("gh", "api", "user", "--jq", ".login",
                    capture_output=True).stdout.strip()

    os.makedirs(args.workdir, exist_ok=True)
    for repo in repos:
        entry = metadata.get(repo.lower())
        if entry is None:
            print(f"\n=== {repo}\n  ! no tutorials_metadata.yml entry - skipped", flush=True)
            continue
        process(repo, entry, args.workdir, args.push, login)

    if not args.push:
        print(f"\nDry run. Clones and edits are in {args.workdir}. "
              "Re-run with --push to open the PRs.")


if __name__ == "__main__":
    main()
