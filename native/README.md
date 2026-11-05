# Ledger (native)

A native iPhone and iPad business simulation in SwiftUI. Double-entry books, countries with their own tax and labour rules, companies, groups, hiring, banking and more.

## Folders

- `Engine/`: Swift package with all rules (pure Swift, no UI). Tests in `Engine/Tests`.
- `App/`: the SwiftUI app (`App/Ledger`, project generated from `App/project.yml` with xcodegen). Views are thin and read the engine through `GameStore`.
- `design/`: mockups and design reference files.
- `tools/`: scripts that generate data and ids.

## Build and test

Engine tests (Linux or macOS, Swift 6):

```sh
cd native/Engine
swift test --skip BalanceProbe      # full run takes a long time; use --filter <Suite> for quick checks
```

App (macOS with Xcode only):

```sh
cd native/App && xcodegen generate
set -o pipefail && xcodebuild -scheme Ledger -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build | xcbeautify
```

## CI and release

- Pushing to `native-swiftui` runs the engine tests and the app build on macOS (`.github/workflows/native-ios.yml`).
- A green app build on a push that touches `native/**` (not `native/design/**`) publishes an unsigned IPA as a GitHub Release and updates `apps.json`, the AltStore source.
- Update `RELEASE_NOTES.md` at the repository root before pushing; it becomes the release notes and the AltStore "what's new".
- `.github/workflows/native-testflight.yml` is a manual TestFlight upload and needs the App Store Connect secrets set in the repository.
