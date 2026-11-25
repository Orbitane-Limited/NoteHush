# Hosted Actions runner migration

On 2026-11-25, the public repository's registered `NoteHush-Mac-arm64` runner was offline and its label was still used by performance, engineering-delivery, Store-delivery and Automation Mode status workflows. The owner had requested removal of the persistent worker once public GitHub-hosted macOS was available. The repository runner registration was deleted; no other repository runner remains.

The affected native workflows now target GitHub-hosted `macos-26` and pin Xcode 26.6 with `/Applications/Xcode_26.6.app/Contents/Developer`. Each job runs on an isolated hosted VM. The signed Store workflow continues to require its existing `app-store` environment and exposes credentials only to its protected main-branch signing job. The unsigned engineering workflow remains main-only. The Automation Mode status workflow now reports the hosted VM and does not imply anything about the owner's local Mac.

Repository automation coverage rejects any workflow that routes to a self-hosted runner and checks the hosted runner/Xcode configuration for each manually dispatched native workflow. The exact-head CI run is required before merging. No delivery or signing run is claimed by this migration.

The GitHub registration showed offline and the launchd service showed `not running`; the launch agent was unloaded. The dedicated runner installation, its launch-agent plist and its runner-only log directory were removed. No process list was available to the sandbox, so no independent process-table claim is made. The development checkout and personal files were outside the cleanup scope and preserved. Physical-Mac performance runs remain local manual work and are not represented by hosted VM measurements.
