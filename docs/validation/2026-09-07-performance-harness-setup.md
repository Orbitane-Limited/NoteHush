# Performance fixture setup validation

Date: 2026-09-07, approximately 00:29 UTC. Issue #35 remains open. This was a functional isolation/setup check, not a performance benchmark or product-budget acceptance.

Checkout: `79da64ad570136a9a03a2cafdd7a283f95f25531`. Host helper includes directory-URL correction `e21b3ac`. The existing optimized app executable's SHA-256 was `6532c3c7d655ed0fbd8f28e20f4f1a979a19a5abea8ece9f0242712307e4d6f6`. The app still used schema-5 recovery; a final measured baseline must rebuild with the merged #31 migration.

`verify_test_app.py --configuration ReleasePerformance` passed for the separate `pk.codehub.NoteHush.PerformanceTesting` bundle and exactly the four product sandbox entitlements. The host helper compiled successfully. The Xcode build task records for this app also specify Swift `-O` and whole-module optimization for the linked `NoteHushCore` module.

`PerformanceFixtureHarness prepare` passed its missing/invalid UUID rejection checks, launched and normally terminated three separate generated workspaces, and seeded the empty/5 MiB/30 MiB fixtures. `cleanup` then passed and removed their generated directories and manifest. Normal recovery storage was never selected. Setup ran after main CI's complete validation step, including its offline-volume UI case, had finished; only artifact upload remained, and recovery PR CI was still queued. No timing samples were collected.

The preceding setup attempt had failed with `launchFailed`. A focused Foundation check showed equal filesystem paths but unequal URLs when only one carried the app directory's trailing slash. The helper now creates the input URL with an explicit directory hint, preserving the exact bundle-location guard, and reports a wrong-build mismatch separately. The corrected functional run passed. No entitlement, identity requirement or timeout was relaxed.

Local log: `/tmp/notehush-issue35-fixture-prepare-fixed.log`. The complete XCTest measurement run, sample extraction, all-buffer post-measurement verification, app-only Instruments run, and final regression CI remain unverified at this point. This setup result does not establish app speed, GUI input exclusivity, minimum-hardware behavior or App Store readiness.
