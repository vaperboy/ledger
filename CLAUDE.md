# Ledger (native SwiftUI business simulation)
- iOS 17+, SwiftUI app `native/App/Ledger`, Swift package engine `native/Engine`, docs `native/docs`.
- Architecture: engine (pure Swift, double-entry ledger, all rules) + thin SwiftUI views over `GameStore`.
- Binding rules: `native/docs/DECISIONS.md`, `SIMULATION_RULES.md`, `DESIGN_RULES.md`. Full handoff: `native/docs/HANDOFF_PROMPT.md`.

# Token and output rules (strict)
- Never output or rewrite whole files: small edits only. Grep before reading; do not re-read files already seen.
- No conversational intros, explanations or summaries. Short answers, verified results only.
- If a build fails, show only the `error:` lines.
- Agents: max two, local commits only, never push; the lead integrates once per milestone.
- Delete nothing without explicit owner approval.

# Build and test (no Mac here: CI is the compiler)
- The app compiles only on macOS CI. Push to `native-swiftui`; CI runs engine-tests and app-build only. Read only whether app-build failed, then its `error:` lines: `gh api repos/vaperboy/ledger/actions/jobs/<id>/logs | grep "error:"`.
- A green app-build on a push touching `native/**` (not docs/design) auto-publishes the AltStore build. Update root `RELEASE_NOTES.md` first. No screenshots, no separate unsigned-IPA run.
- Engine tests (Linux): `cd native/Engine && PATH=/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH swift test --skip BalanceProbe` (about 30 min: run in background, filter with `--filter <Suite>` for quick checks).
- On a Mac: `set -o pipefail && xcodebuild -scheme Ledger -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build | xcbeautify` (project from `xcodegen generate` in native/App).
