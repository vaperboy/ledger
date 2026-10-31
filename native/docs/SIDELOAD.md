# Installing on your phone without the paid Apple Developer Program

Free route with limits: a free Apple ID signs the app for **7 days** (AltStore refreshes it while AltServer runs on your Mac/PC). The build is an **unsigned IPA** that the IPA workflow publishes as a **GitHub Release** (tag `v<run number>`) and lists in the AltStore source `apps.json`.

## Get a new build
`git push origin native-swiftui:ipa-build --force` (or ask the assistant). The workflow "Native iOS unsigned IPA (GitHub Release + AltStore source)" builds the app with version `1.0.<run>` and build `<run>` (AltStore checks that the app's version equals the source's version), checks that, publishes the Release, and updates `apps.json` on `native-swiftui`.

## Install with AltStore (recommended)
1. Install AltStore (altstore.io) on the phone with AltServer on a computer, as its guide says.
2. In AltStore > Sources > + , add `https://raw.githubusercontent.com/vaperboy/ledger/native-swiftui/apps.json`.
3. Browse the source, tap Ledger > Free. To update, open AltStore > Updates.
If AltStore says the downloaded version does not match the source, remove the source and app and add the source again so it re-reads `apps.json`; the workflow now stamps matching versions.

## Or install with Sideloadly
Download `Ledger-unsigned.ipa` from the latest Release, drag it into Sideloadly (sideloadly.io), enter your Apple ID, Start. Then Settings > General > VPN & Device Management > Trust, and on iOS 16+ turn on Developer Mode.

Limits: no iCloud or push features (the app uses none). Saves stay on the device between reinstalls with the same bundle id.
