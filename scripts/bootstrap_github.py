#!/usr/bin/env python3
"""Create missing roadmap objects. Requires authenticated gh repository admin access."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = "CodeHubdotPk/NoteHush"
BASE = f"repos/{REPO}"


def api(path, method="GET", payload=None):
    command = ["gh", "api", path, "--method", method]
    if payload is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def main():
    roadmap = json.loads((ROOT / "docs/roadmap.json").read_text())
    labels = {item["name"] for item in api(f"{BASE}/labels?per_page=100")}
    desired = {"type:bug": "d73a4a", "priority:P1": "b60205"}
    for item in roadmap["issues"]:
        desired[f'type:{item["type"]}'] = "0075ca"
        desired[f'area:{item["area"]}'] = "5319e7"
    for name, color in desired.items():
        if name not in labels:
            api(f"{BASE}/labels", "POST", {"name": name, "color": color})
    milestones = {item["title"]: item for item in api(f"{BASE}/milestones?state=all&per_page=100")}
    for item in roadmap["milestones"]:
        if item["title"] not in milestones:
            milestones[item["title"]] = api(f"{BASE}/milestones", "POST", item)
    existing = {item["title"]: item for item in api(f"{BASE}/issues?state=all&per_page=100")
                if "pull_request" not in item}
    mapped = {}
    for item in roadmap["issues"]:
        title = item["title"]
        milestone = roadmap["milestones"][item["milestone"]]["title"]
        if title not in existing:
            dependencies = ", ".join(f'#{mapped[index]["number"]}' for index in item["depends"]) or "None"
            body = (f'## Outcome\n\n{title}.\n\nRequirements: {item["requirements"]}.\n\n'
                    f'## Dependencies\n\n{dependencies}\n\n## Acceptance criteria\n\n' +
                    "\n".join(f"- [ ] {criterion}" for criterion in item["acceptance"]) +
                    "\n\n## Delivery\n\nUse a dedicated `issue-N/description` branch and PR with `Closes #N`. "
                    "Run the relevant checks in TESTING.md and record executed results. Do not mark unverified gates complete.\n")
            existing[title] = api(f"{BASE}/issues", "POST", {
                "title": title, "body": body, "milestone": milestones[milestone]["number"],
                "labels": [f'type:{item["type"]}', f'area:{item["area"]}', "priority:P1"]})
        mapped[item["id"]] = existing[title]
        print(f'{item["id"]:02}: {existing[title]["html_url"]}', flush=True)
    lines = ["# GitHub Roadmap", "", "Generated from roadmap.json. GitHub is the live status source.", ""]
    for index, milestone in enumerate(roadmap["milestones"]):
        remote = milestones[milestone["title"]]
        lines += [f'## [{milestone["title"]}]({remote["html_url"]})', ""]
        for item in roadmap["issues"]:
            if item["milestone"] == index:
                issue = mapped[item["id"]]
                lines.append(f'- [#{issue["number"]}: {item["title"]}]({issue["html_url"]})')
        lines.append("")
    (ROOT / "docs/GITHUB_ROADMAP.md").write_text("\n".join(lines))


if __name__ == "__main__":
    main()
