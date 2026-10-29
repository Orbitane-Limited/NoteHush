#!/usr/bin/env python3
"""Read-only App Store Connect build checks, using a short-lived team-key JWT."""
import base64
import json
import re
import subprocess
import time
import urllib.parse
import urllib.request
import uuid

from app_store_checks import BUNDLE_ID, require, tool_environment, validate_build_numbers

ORIGIN = "https://api.appstoreconnect.apple.com"


def base64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def jose_signature(der):
    """OpenSSL emits DER ECDSA; ES256 JWT uses two unsigned 32-byte integers."""
    require(8 <= len(der) <= 72 and der[0] == 0x30 and der[1] == len(der) - 2,
            "Unexpected ECDSA signature envelope")
    cursor, result = 2, b""
    for _ in range(2):
        require(cursor + 2 <= len(der) and der[cursor] == 2, "Invalid ECDSA integer")
        length = der[cursor + 1]
        cursor += 2
        value = der[cursor:cursor + length]
        require(1 <= length <= 33 and len(value) == length and value[0] < 128,
                "Invalid ECDSA integer length or sign")
        require(length == 1 or value[0] != 0 or value[1] >= 128,
                "Noncanonical ECDSA integer")
        number = int.from_bytes(value, "big")
        require(0 < number < (1 << 256), "ECDSA integer outside ES256 range")
        result += number.to_bytes(32, "big")
        cursor += length
    require(cursor == len(der), "Trailing ECDSA signature bytes")
    return result


def make_token(key_path, key_id, issuer_id, app_id):
    require(re.fullmatch(r"[A-Z0-9]{10}", key_id), "Invalid App Store Connect key ID")
    require(isinstance(issuer_id, str) and str(uuid.UUID(issuer_id)) == issuer_id.lower(),
            "Invalid App Store Connect issuer")
    require(re.fullmatch(r"[1-9]\d*", app_id), "Invalid App Store Connect app ID")
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 300, "aud": "appstoreconnect-v1",
               "scope": [f"GET /v1/apps/{app_id}", f"GET /v1/apps/{app_id}/builds"]}
    signing_input = b".".join(base64url(json.dumps(value, separators=(",", ":")).encode())
                              for value in (header, payload))
    result = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", str(key_path)],
                            input=signing_input, capture_output=True, check=False,
                            env=tool_environment(), timeout=30)
    require(result.returncode == 0, "Unable to sign the App Store Connect request")
    return (signing_input + b"." + base64url(jose_signature(result.stdout))).decode("ascii")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("App Store Connect redirect refused")


class StoreConnect:
    def __init__(self, key_path, key_id, issuer_id, app_id):
        require(re.fullmatch(r"[1-9]\d*", app_id), "Invalid App Store Connect app ID")
        self.credentials = key_path, key_id, issuer_id, app_id
        self.app_path = f"/v1/apps/{app_id}"
        self.opener = urllib.request.build_opener(NoRedirect())

    def get(self, url):
        parsed = urllib.parse.urlsplit(url)
        require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
                and not parsed.fragment and parsed.path in {self.app_path, self.app_path + "/builds"},
                "Unexpected App Store Connect pagination destination")
        request = urllib.request.Request(url, headers={
            "Authorization": "Bearer " + make_token(*self.credentials), "Accept": "application/json"})
        with self.opener.open(request, timeout=30) as response:
            contents = response.read(8 * 1024 * 1024 + 1)
        require(len(contents) <= 8 * 1024 * 1024, "App Store response exceeded the size guard")
        payload = json.loads(contents)
        require(isinstance(payload, dict) and "errors" not in payload, "App Store request failed")
        return payload

    def check_next_build(self, candidate):
        app = self.get(ORIGIN + self.app_path).get("data", {})
        require(app.get("type") == "apps" and app.get("id") == self.credentials[3]
                and app.get("attributes", {}).get("bundleId") == BUNDLE_ID,
                "App Store app record does not match NoteHush")
        url = ORIGIN + self.app_path + "/builds?limit=200&fields%5Bbuilds%5D=version"
        seen, builds = set(), []
        while url:
            require(isinstance(url, str) and url not in seen and len(seen) < 1000,
                    "Invalid or excessive App Store pagination")
            seen.add(url)
            payload = self.get(url)
            require(isinstance(payload.get("data"), list) and isinstance(payload.get("links"), dict),
                    "Incomplete App Store build listing")
            builds.extend(payload["data"])
            url = payload["links"].get("next")
            require(url is None or isinstance(url, str) and bool(url), "Invalid next-page link")
        return validate_build_numbers(candidate, builds)
