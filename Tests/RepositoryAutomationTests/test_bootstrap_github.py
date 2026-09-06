"""No live GitHub calls: test the mutation boundary and transfer/idempotence behavior."""
import argparse
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "bootstrap_github", Path(__file__).resolve().parents[2] / "scripts/bootstrap_github.py")
bootstrap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bootstrap)

OLD = "Previous-Owner/NoteHush"
NEW = "Canonical-Owner/NoteHush"
BASE = f"repos/{NEW}"
ROADMAP = {
    "milestones": [{"title": "Foundation", "description": "Generated fixture"}],
    "issues": [
        {"id": 1, "milestone": 0, "title": "First", "type": "test", "area": "quality",
         "depends": [], "requirements": "Fixture", "acceptance": ["Preserve state"]},
        {"id": 2, "milestone": 0, "title": "Second", "type": "test", "area": "quality",
         "depends": [1], "requirements": "Fixture", "acceptance": ["Preserve Unicode 👩🏽‍💻"]},
    ],
}


class FakeGitHub:
    def __init__(self):
        self.calls = []
        self.labels = [{"name": name} for name in bootstrap.desired_labels(ROADMAP)]
        self.milestones = [{"title": "Foundation", "number": 7}]
        self.issues = [
            {"title": "First", "number": 42, "body": "Human edits\n- [x] Keep this"},
            {"title": "Second", "number": 43, "body": "Manual follow-up and evidence"},
            {"title": "First", "number": 44, "pull_request": {}},
        ]
        self.fail_listing = False

    def request(self, path, method="GET", payload=None, *, paginate=False):
        self.calls.append((path, method, copy.deepcopy(payload), paginate))
        if path == f"repos/{OLD}" and method == "GET":
            return {"full_name": NEW}
        if not path.startswith(BASE + "/"):
            raise AssertionError("All collection reads and writes must use canonical scope")
        collection = path.split("/")[-1].split("?")[0]
        if self.fail_listing and collection == "issues" and method == "GET":
            raise subprocess.CalledProcessError(1, ["gh", "api"])
        objects = getattr(self, collection)
        if method == "GET":
            if not paginate:
                raise AssertionError("Collection reads must include every page")
            return copy.deepcopy(objects)
        if method != "POST":
            raise AssertionError("Existing objects must not be edited")
        result = copy.deepcopy(payload)
        if collection != "labels":
            result["number"] = max((x["number"] for x in objects), default=0) + 1
        objects.append(result)
        return copy.deepcopy(result)

    @property
    def mutations(self):
        return [call for call in self.calls if call[1] != "GET"]


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)
        self.remote = FakeGitHub()

    def run_bootstrap(self, **kwargs):
        return bootstrap.bootstrap(OLD, copy.deepcopy(ROADMAP), request=self.remote.request, **kwargs)

    def test_transfer_uses_canonical_routes_and_preserves_existing_bodies(self):
        before = copy.deepcopy(self.remote.issues)
        rendered = self.run_bootstrap(apply=True)
        self.assertEqual(self.remote.mutations, [])
        self.assertEqual(self.remote.issues, before)
        self.assertIn(f"https://github.com/{NEW}/issues/42", rendered)
        self.assertIn(f"https://github.com/{NEW}/issues/43", rendered)
        self.assertNotIn(OLD, rendered)

    def test_preview_does_not_create_missing_objects(self):
        self.remote.labels = []
        self.remote.milestones = []
        self.remote.issues = []
        self.assertIsNone(self.run_bootstrap())
        self.assertEqual(self.remote.mutations, [])

    def test_apply_creates_dependencies_then_second_run_is_idempotent(self):
        self.remote.labels = []
        self.remote.milestones = []
        self.remote.issues = []
        rendered = self.run_bootstrap(apply=True)
        self.assertIn(f"https://github.com/{NEW}/issues/2", rendered)
        self.assertEqual(len(self.remote.issues), 2)
        self.assertEqual(len(self.remote.milestones), 1)
        body = self.remote.issues[1]["body"]
        self.assertIn("## Dependencies\n\n#1\n", body)
        self.assertIn("Preserve Unicode 👩🏽‍💻", body)
        self.assertNotIn("\\n", body)
        writes = len(self.remote.mutations)
        self.run_bootstrap(apply=True)
        self.assertEqual(len(self.remote.mutations), writes)

    def test_failed_listing_cannot_create_labels_or_replace_roadmap(self):
        self.remote.labels = []
        self.remote.fail_listing = True
        with tempfile.TemporaryDirectory() as folder:
            root = self.fixture_root(folder)
            with self.assertRaises(subprocess.CalledProcessError):
                bootstrap.main(["--repo", OLD, "--apply", "--write-roadmap"],
                               request=self.remote.request, root=root)
            self.assertEqual((root / "docs/GITHUB_ROADMAP.md").read_text(), "preserve existing")
        self.assertEqual(self.remote.mutations, [])

    def test_duplicate_desired_title_fails_before_any_mutation(self):
        self.remote.labels = []
        self.remote.issues.append({"title": "First", "number": 99})
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            self.run_bootstrap(apply=True)
        self.assertEqual(self.remote.mutations, [])

    def test_invalid_dependency_order_fails_before_network(self):
        roadmap = copy.deepcopy(ROADMAP)
        roadmap["issues"].reverse()
        with self.assertRaisesRegex(ValueError, "dependencies"):
            bootstrap.bootstrap(OLD, roadmap, apply=True, request=self.remote.request)
        self.assertEqual(self.remote.calls, [])

    def test_repo_option_rejects_paths_urls_placeholders_and_missing_argument(self):
        for value in ["../repo", "owner/..", "owner/repo?query", "{owner}/{repo}",
                      "https://github.com/owner/repo", "owner/repo/extra", "owner/repo\n"]:
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                bootstrap.repository_name(value)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            bootstrap.main([], request=self.remote.request)
        self.assertEqual(self.remote.calls, [])

    def test_preview_preserves_file_and_explicit_render_uses_only_reads(self):
        before = copy.deepcopy(self.remote.issues)
        with tempfile.TemporaryDirectory() as folder:
            root = self.fixture_root(folder)
            bootstrap.main(["--repo", OLD], request=self.remote.request, root=root)
            self.assertEqual((root / "docs/GITHUB_ROADMAP.md").read_text(), "preserve existing")
            bootstrap.main(["--repo", OLD, "--write-roadmap"], request=self.remote.request, root=root)
            self.assertIn(f"https://github.com/{NEW}/issues/42",
                          (root / "docs/GITHUB_ROADMAP.md").read_text())
        self.assertEqual(self.remote.mutations, [])
        self.assertEqual(self.remote.issues, before)

    def test_incomplete_preview_cannot_replace_roadmap(self):
        self.remote.issues = []
        with tempfile.TemporaryDirectory() as folder:
            root = self.fixture_root(folder)
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                bootstrap.main(["--repo", OLD, "--write-roadmap"],
                               request=self.remote.request, root=root)
            self.assertEqual((root / "docs/GITHUB_ROADMAP.md").read_text(), "preserve existing")
        self.assertEqual(self.remote.mutations, [])

    def test_transport_flattens_all_pages_and_pins_host(self):
        pages = [[{"title": "unrelated", "number": 1}], [{"title": "First", "number": 42}]]
        with patch.object(bootstrap.subprocess, "run") as run:
            run.return_value.stdout = json.dumps(pages)
            values = bootstrap.api(BASE + "/issues?state=all&per_page=100", paginate=True)
            self.assertEqual(values, pages[0] + pages[1])
            command = run.call_args.args[0]
            self.assertIn("--paginate", command)
            self.assertIn("--slurp", command)
            self.assertEqual(command[command.index("--hostname") + 1], "github.com")
            self.assertEqual(command[command.index("--method") + 1], "GET")

    def test_transport_sends_exact_json_through_stdin_and_rejects_write_pagination(self):
        payload = {"title": "Fixture", "body": "actual newline\n`literal` $(literal)"}
        with patch.object(bootstrap.subprocess, "run") as run:
            run.return_value.stdout = '{"number": 12}'
            result = bootstrap.api(BASE + "/issues", "POST", payload)
            self.assertEqual(result["number"], 12)
            self.assertEqual(json.loads(run.call_args.kwargs["input"]), payload)
            self.assertEqual(run.call_args.args[0][-2:], ["--input", "-"])
            self.assertNotIn("shell", run.call_args.kwargs)
            calls = run.call_count
            with self.assertRaises(ValueError):
                bootstrap.api(BASE + "/issues", "POST", payload, paginate=True)
            self.assertEqual(run.call_count, calls)

    @staticmethod
    def fixture_root(folder):
        root = Path(folder)
        (root / "docs").mkdir()
        (root / "docs/roadmap.json").write_text(json.dumps(ROADMAP))
        (root / "docs/GITHUB_ROADMAP.md").write_text("preserve existing")
        return root


if __name__ == "__main__":
    unittest.main()
