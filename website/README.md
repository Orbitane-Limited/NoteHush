# Public NoteHush pages

These static HTML/CSS pages use only local assets. There are no scripts, external fonts, analytics, contact forms or backend dependencies. They are prepared for a public HTTPS host; nothing in this directory has been published.

Generate a visibly marked, non-indexable local preview:

```sh
python3 scripts/build_site.py --preview --output build/site-preview
```

The preview deliberately shows that publisher details are placeholders. Do not deploy it. For publication, copy `publisher.example.json` to an ignored local file under `build/`, fill in the confirmed legal publisher, public support email, final site URL, actual hosting provider and its privacy URL, and the policy's effective date. Review the policy's support retention/deletion wording with the publisher. Then generate a new output directory:

```sh
python3 scripts/build_site.py --config build/publisher.json --output build/site-public-candidate
```

Missing fields, placeholder domains, non-HTTPS web destinations and malformed contact information fail before public output is created. HTML escapes publisher values. The builder refuses an existing destination, writes a file-hash report alongside the output, and always leaves `publicHTTPSVerified` false: generating files does not verify deployment, ownership, policy approval or availability.

Deploy only the generated directory to the confirmed public host. Inspect home/support/privacy in a browser without GitHub or Apple authentication, verify HTTPS and working email/navigation links, and confirm the host adds no tracking or access gate. Record actual URL, source commit, report and deployment result in `docs/validation/`. A private GitHub repository cannot be used as the public support/privacy page. Choose a host/repository plan that supports anonymous pages; do not change this app repository's visibility to work around a restriction.

After publication, wire the verified support/privacy URLs into the app's Help menu and Store metadata. The app should open them in the user's browser on request; it does not need a network entitlement. This remains issue #15 work. Store screenshots are separate and must come from the actual final app using isolated fixtures.
