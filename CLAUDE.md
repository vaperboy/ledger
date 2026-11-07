# Ledger (native SwiftUI business simulation)
- iOS 17+, SwiftUI app `native/App/Ledger`, Swift package engine `native/Engine`. See `native/README.md`.
- Architecture: engine (pure Swift, double-entry ledger, all rules) + thin SwiftUI views over `GameStore`.

# Working rules
- Short answers, verified results only. Say a thing works only after a test or CI run showed it.
- Comments say what and why in one or two lines. No request, brief, stage or process references in code.
- Rewrite whole screens and files when a redesign calls for it; remove UI that a redesign replaces.
- Agents: as many as useful, each on its own files, local commits only; the lead integrates and pushes.

# Build and test (no Mac here: CI is the compiler)
- The app compiles only on macOS CI. Push to `native-swiftui`; CI runs engine-tests and app-build. Read only whether app-build failed, then its `error:` lines: `gh api repos/vaperboy/ledger/actions/jobs/<id>/logs | grep "error:"`. If a build fails, show only the `error:` lines.
- A green app-build on a push touching `native/**` (not design) auto-publishes the AltStore build. Update root `RELEASE_NOTES.md` first.
- Engine tests (Linux): `cd native/Engine && PATH=/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH swift test --skip BalanceProbe` (about 30 min: run in background, filter with `--filter <Suite>` for quick checks).
- On a Mac: `set -o pipefail && xcodebuild -scheme Ledger -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build | xcbeautify` (project from `xcodegen generate` in native/App).
