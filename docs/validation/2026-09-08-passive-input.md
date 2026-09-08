# Passive input observation — 2026-09-08 UTC

Source: `5f0739086195d15da70c8a285a70df594ec6ae90`, isolated DebugUITesting
app with the extended #29 diagnostic. The app's three executable artifacts matched
the recorded build hashes. Exact product sandbox entitlements passed before and
after launch. This observation followed the unexplained edit during the earlier
interaction profile; keyboard-driven acceptance remained paused.

A standalone Swift 6 helper launched one fresh UUID workspace and one generated
file containing the published small Unicode/CRLF oracle. It used no keyboard or
mouse events, accessibility operations or pasteboard APIs. It sampled only the
returned app's active/terminated state, observed 31.006985458 seconds while active,
and requested normal termination of that exact identified process. The app stopped.

The strict trace validator accepted all three records: installation, activation
and shutdown. **Zero key events were observed.** The independent recovery check
validated the schema-6 checksum, both complete generated buffers and blob checksums,
UTF-8/UTF-16 counts, tab order, active tab, unchanged selections and original source
bytes. The final diagnostic classified the selected buffer as the original oracle;
the trace remained mode 0600. All fixture and trace evidence was retained.

Private evidence is under the repository's
`build/manual-acceptance/passive-input-20260908/`; the launcher and verifier sources
are retained alongside the other ignored manual helpers. No unexpected text,
clipboard data or external process information was logged.

This is one passive window, **not** a functional Find/Undo test or proof of future
exclusive input. It does not identify the earlier edit's source, exercise the new
key-event metadata with an actual key, resolve the Xcode automation authorization,
or close #29. It permits further investigation without claiming the intermittent
input issue is fixed.
