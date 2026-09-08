"""Keep publisher placeholders and unsafe links out of generated public pages."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("site_builder", ROOT / "scripts/build_site.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicSiteTests(unittest.TestCase):
    def configuration(self):
        # Syntactic fixtures only; these tests never access or deploy a domain.
        return {"publisher_name": "Fixture Publisher & <Company>", "support_email": "support@notehush-fixture.com",
                "site_url": "https://notehush-fixture.com", "hosting_provider": "Fixture Host",
                "hosting_privacy_url": "https://hosting-fixture.com/privacy", "privacy_effective_date": "2026-09-08"}

    def testMissingPublisherFieldsFailBeforeCreatingOutput(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "public"
            for configuration in ({}, {key: None for key in module.FIELDS}):
                with self.assertRaises(ValueError):
                    module.build(destination, configuration)
                self.assertFalse(destination.exists())

    def testPlaceholderLocalAndExecutableDestinationsAreRejected(self):
        for url in ["https://example.invalid", "https://example.com", "http://notehush-fixture.com",
                    "javascript:alert(1)", "https://127.0.0.1", "https://10.0.0.1", "https://printer.local",
                    "https://user:password@notehush-fixture.com", "https://notehush-fixture.com\"bad"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                module.https_url(url)

    def testPublicCopyEscapesPublisherTextAndDoesNotClaimLiveVerification(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "public"
            report = module.build(destination, self.configuration())
            self.assertFalse(report["preview"])
            self.assertFalse(report["publicHTTPSVerified"])
            for name in ("index.html", "support.html", "privacy.html"):
                contents = (destination / name).read_text()
                self.assertIn("Fixture Publisher &amp; &lt;Company&gt;", contents)
                self.assertNotIn("{{", contents)
                self.assertNotIn("<script", contents)
                self.assertNotIn("example.invalid", contents)
            self.assertTrue((destination / "assets/icon.svg").is_file())

    def testPreviewIsExplicitAndExistingOutputAndReportsArePreserved(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "preview"
            report = module.build(destination, preview=True)
            self.assertTrue(report["preview"])
            self.assertIn("Not approved for publication", (destination / "privacy.html").read_text())
            self.assertIn("noindex,nofollow", (destination / "privacy.html").read_text())
            original = (destination / "privacy.html").read_bytes()
            with self.assertRaises(ValueError):
                module.build(destination, self.configuration())
            self.assertEqual((destination / "privacy.html").read_bytes(), original)
            another = Path(directory) / "other"
            another.with_suffix(".json").write_text("preexisting report")
            with self.assertRaises(ValueError):
                module.build(another, self.configuration())
            self.assertFalse(another.exists())
            self.assertEqual(another.with_suffix(".json").read_text(), "preexisting report")


if __name__ == "__main__":
    unittest.main()
