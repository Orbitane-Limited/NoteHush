#!/usr/bin/env python3
"""Build NoteHush's static public pages or a visibly marked local preview."""
import argparse
from datetime import date
import hashlib
import html
import ipaddress
import json
from pathlib import Path
import re
import shutil
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
FIELDS = {"publisher_name", "support_email", "site_url", "hosting_provider",
          "hosting_privacy_url", "privacy_effective_date"}


def https_url(value):
    parsed = urllib.parse.urlsplit(value)
    try:
        ipaddress.ip_address(parsed.hostname or "")
    except ValueError:
        pass
    else:
        raise ValueError("Use the confirmed public hostname, not an IP address")
    if (parsed.scheme != "https" or not parsed.hostname or "." not in parsed.hostname
            or parsed.username or parsed.password or parsed.port or parsed.query or parsed.fragment
            or parsed.hostname in {"example.com", "example.org", "example.net"}
            or not re.fullmatch(r"[a-z0-9-]+(?:\.[a-z0-9-]+)+", parsed.hostname)
            or parsed.hostname.endswith((".invalid", ".localhost", ".test", ".example", ".local", ".internal"))):
        raise ValueError("Use the confirmed public HTTPS address without query parameters")
    return value.rstrip("/")


def validate_publisher(configuration):
    if set(configuration) != FIELDS or any(not isinstance(value, str) or not value.strip()
                                          for value in configuration.values()):
        raise ValueError("Fill every publisher field before building public pages")
    result = {key: value.strip() for key, value in configuration.items()}
    result["site_url"] = https_url(result["site_url"])
    result["hosting_privacy_url"] = https_url(result["hosting_privacy_url"])
    if not re.fullmatch(r"[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", result["support_email"]):
        raise ValueError("Use a public support email address")
    domain = result["support_email"].split("@", 1)[1].lower()
    https_url("https://" + domain)
    if date.fromisoformat(result["privacy_effective_date"]).isoformat() != result["privacy_effective_date"]:
        raise ValueError("Use an ISO privacy effective date")
    return result


def build(destination, configuration=None, *, preview=False):
    if preview:
        values = {
            "publisher_name": "Publisher to be confirmed", "support_email": "support@example.invalid",
            "site_url": "https://example.invalid", "hosting_provider": "Hosting provider to be confirmed",
            "hosting_privacy_url": "https://example.invalid/privacy", "privacy_effective_date": "Not published",
        }
    else:
        values = validate_publisher(configuration)
    report_path = destination.with_suffix(".json")
    if destination.exists() or destination.is_symlink() or report_path.exists() or report_path.is_symlink():
        raise ValueError("Choose a new output directory; existing files are never replaced")
    destination.mkdir(parents=True)
    (destination / "assets").mkdir()
    substitutions = {key.upper(): html.escape(value, quote=True) for key, value in values.items()}
    substitutions["YEAR"] = str(date.today().year)
    for name in ("index.html", "support.html", "privacy.html"):
        page = (ROOT / "website" / name).read_text()
        page = re.sub(r"\{\{([A-Z_]+)\}\}", lambda match: substitutions[match[1]], page)
        if "{{" in page or "}}" in page:
            raise ValueError("Unresolved website template field")
        if preview:
            page = page.replace("</head>", '<meta name="robots" content="noindex,nofollow">\n</head>')
            page = page.replace("<body>", '<body>\n<aside class="preview-banner">Local preview — publisher details are placeholders. Not approved for publication.</aside>')
        (destination / name).write_text(page)
    shutil.copyfile(ROOT / "website/style.css", destination / "style.css")
    shutil.copyfile(ROOT / "Design/NoteHushIcon.svg", destination / "assets/icon.svg")
    (destination / ".nojekyll").touch()
    report = {"preview": preview, "publisherFieldsProvided": not preview,
              "publicHTTPSVerified": False, "files": {
                  str(path.relative_to(destination)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted(destination.rglob("*")) if path.is_file()}}
    with report_path.open("x") as stream:
        stream.write(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--preview", action="store_true")
    mode.add_argument("--config", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    configuration = json.loads(arguments.config.read_text()) if arguments.config else None
    build(arguments.output, configuration, preview=arguments.preview)
    print("Static pages generated. Public HTTPS deployment has not been verified.")


if __name__ == "__main__":
    main()
