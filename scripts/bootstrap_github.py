#!/usr/bin/env python3
"""Preview/create missing roadmap objects in an explicitly selected GitHub repository."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def repository_name(value):
    pattern = r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9_.-]+"
    if not re.fullmatch(pattern, value) or value.split("/")[-1] in {".", ".."}:
        raise argparse.ArgumentTypeError("Use OWNER/REPOSITORY, without a URL, query or placeholders")
    return value


def api(path, method="GET", payload=None, *, paginate=False):
    command = ["gh", "api", "--hostname", "github.com", path, "--method", method]
    if paginate:
        if method != "GET" or payload is not None:
            raise ValueError("Only collection reads can paginate")
        command += ["--paginate", "--slurp"]
    if payload is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True, check=True)
    value = json.loads(result.stdout) if result.stdout.strip() else None
    if paginate:
        if not isinstance(value, list) or any(not isinstance(page, list) for page in value):
            raise ValueError("Expected a paginated collection")
        return [item for page in value for item in page]
    return value


def index_titles(items, wanted):
    indexed = {}
    for item in items:
        if "pull_request" in item or item["title"] not in wanted:
            continue
        title = item["title"]
        if title in indexed:
            raise ValueError(f"Ambiguous existing roadmap title: {title}")
        if type(item["number"]) is not int or item["number"] <= 0:
            raise ValueError("Invalid GitHub object number")
        indexed[title] = item
    return indexed


def desired_labels(roadmap):
    desired = {"type:bug": "d73a4a", "priority:P1": "b60205"}
    for item in roadmap["issues"]:
        desired[f'type:{item["type"]}'] = "0075ca"
        desired[f'area:{item["area"]}'] = "5319e7"
    return desired


def validate_roadmap(roadmap):
    seen = set()
    titles = set()
    milestone_titles = [item["title"] for item in roadmap["milestones"]]
    if len(set(milestone_titles)) != len(milestone_titles):
        raise ValueError("Duplicate roadmap milestone title")
    for item in roadmap["issues"]:
        if item["id"] in seen or item["title"] in titles:
            raise ValueError("Duplicate roadmap issue identity/title")
        if not set(item["depends"]).issubset(seen):
            raise ValueError("Roadmap dependencies must precede their dependents")
        if type(item["milestone"]) is not int or not 0 <= item["milestone"] < len(milestone_titles):
            raise ValueError("Invalid roadmap milestone index")
        seen.add(item["id"])
        titles.add(item["title"])


def issue_body(item, mapped):
    dependencies = ", ".join(f'#{mapped[index]["number"]}' for index in item["depends"]) or "None"
    return (f'## Outcome\n\n{item["title"]}.\n\nRequirements: {item["requirements"]}.\n\n'
            f'## Dependencies\n\n{dependencies}\n\n## Acceptance criteria\n\n' +
            "\n".join(f"- [ ] {criterion}" for criterion in item["acceptance"]) +
            "\n\n## Delivery\n\nUse a dedicated `issue-N/description` branch and PR with `Closes #N`. "
            "Run the relevant checks in TESTING.md and record executed results. "
            "Do not mark unverified gates complete.\n")


def bootstrap(repo, roadmap, *, apply=False, request=api):
    validate_roadmap(roadmap)
    # GET can follow a transfer redirect. Use GitHub's canonical identity for all
    # subsequent requests, especially mutations, instead of the former endpoint.
    selected = repository_name(repo)
    canonical = repository_name(request(f"repos/{selected}")["full_name"])
    base = f"repos/{canonical}"
    labels = {item["name"] for item in request(f"{base}/labels?per_page=100", paginate=True)}
    desired = desired_labels(roadmap)
    milestones = index_titles(
        request(f"{base}/milestones?state=all&per_page=100", paginate=True),
        {item["title"] for item in roadmap["milestones"]})
    existing = index_titles(
        request(f"{base}/issues?state=all&per_page=100", paginate=True),
        {item["title"] for item in roadmap["issues"]})
    # Finish every read/preflight before any write. A failed listing cannot look
    # like an empty repository and cause duplicate objects to be created.
    missing = {
        "labels": [name for name in desired if name not in labels],
        "milestones": [item["title"] for item in roadmap["milestones"]
                       if item["title"] not in milestones],
        "issues": [item["title"] for item in roadmap["issues"] if item["title"] not in existing],
    }
    print(f"Repository: {canonical}", flush=True)
    print(json.dumps({"mode": "apply" if apply else "preview", "missing": missing}), flush=True)
    if not apply and any(missing.values()):
        return None
    if apply:
        for name in missing["labels"]:
            request(f"{base}/labels", "POST", {"name": name, "color": desired[name]})
        for item in roadmap["milestones"]:
            if item["title"] not in milestones:
                milestones[item["title"]] = request(f"{base}/milestones", "POST", item)
    mapped = {}
    for item in roadmap["issues"]:
        title = item["title"]
        milestone = roadmap["milestones"][item["milestone"]]["title"]
        if title not in existing:
            existing[title] = request(f"{base}/issues", "POST", {
                "title": title, "body": issue_body(item, mapped),
                "milestone": milestones[milestone]["number"],
                "labels": [f'type:{item["type"]}', f'area:{item["area"]}', "priority:P1"]})
        mapped[item["id"]] = existing[title]
        print(f'{item["id"]:02}: https://github.com/{canonical}/issues/{existing[title]["number"]}',
              flush=True)
    return render_roadmap(canonical, roadmap, milestones, mapped)


def render_roadmap(repo, roadmap, milestones, mapped):
    lines = ["# GitHub Roadmap", "", "Generated from roadmap.json. GitHub is the live status source.", ""]
    for index, milestone in enumerate(roadmap["milestones"]):
        number = milestones[milestone["title"]]["number"]
        lines += [f'## [{milestone["title"]}](https://github.com/{repo}/milestone/{number})', ""]
        for item in roadmap["issues"]:
            if item["milestone"] == index:
                number = mapped[item["id"]]["number"]
                lines.append(f'- [#{number}: {item["title"]}](https://github.com/{repo}/issues/{number})')
        lines.append("")
    lines += [f"Additional implementation issues and current status: [GitHub issues](https://github.com/{repo}/issues).", ""]
    return "\n".join(lines)


def main(argv=None, *, request=api, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=repository_name, help="Explicit OWNER/REPOSITORY on github.com")
    parser.add_argument("--apply", action="store_true", help="Create missing objects; existing bodies remain untouched")
    parser.add_argument("--write-roadmap", action="store_true", help="Regenerate docs/GITHUB_ROADMAP.md when all objects exist")
    args = parser.parse_args(argv)
    roadmap = json.loads((root / "docs/roadmap.json").read_text())
    rendered = bootstrap(args.repo, roadmap, apply=args.apply, request=request)
    if args.write_roadmap:
        if rendered is None:
            parser.error("Roadmap objects are missing; review the preview before using --apply")
        (root / "docs/GITHUB_ROADMAP.md").write_text(rendered)


if __name__ == "__main__":
    main()
