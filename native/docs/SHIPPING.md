# Shipping Ledger (iOS)

Current project settings (`native/App/project.yml`, XcodeGen): display name **Ledger**, bundle id `com.example.ledger` (placeholder), version 1.0.0 build 1, iOS 17.0 minimum, iPhone + iPad, dark UI, portrait + landscape (iPad all four), launch screen colour #0F1011, app icon set `Assets.xcassets/AppIcon.appiconset` (placeholder: champagne serif L on dark, made by `native/tools/make_app_icon.py`). No privacy permission strings are needed (no camera, photos, location, notifications or tracking). Signing is left on Automatic and is not configured here.

## A. Sideload the unsigned IPA (Sideloadly or AltStore)

1. Get the unsigned IPA from CI (the build artifact), or build it on a Mac:
   `cd native/App && xcodegen generate && xcodebuild -scheme Ledger -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO`
   then `mkdir Payload && cp -R build/Build/Products/Release-iphoneos/Ledger.app Payload/ && zip -r Ledger.ipa Payload`.
2. Sideloadly (Mac or Windows): connect the iPhone, trust the computer, drag `Ledger.ipa` in, enter your Apple ID, press Start. Sideloadly re-signs it with your free certificate.
3. AltStore: install AltServer on the computer, install AltStore on the phone, open the IPA in AltStore (My Apps, +).
4. On the phone: Settings, General, VPN and Device Management, trust your Apple ID. Developer Mode (Settings, Privacy and Security) must be on for iOS 16+.
5. Free Apple IDs: the app expires after 7 days and must be refreshed (AltStore refreshes automatically while on the same Wi-Fi as AltServer); at most 3 sideloaded apps and 10 App IDs a week. A paid developer account lasts a year.

## B. TestFlight (later)

1. Join the Apple Developer Program, then create the App ID in the developer portal with the final bundle id.
2. In `native/App/project.yml` set `bundleIdPrefix`, `PRODUCT_BUNDLE_IDENTIFIER` (and the `.uitests` id) and add `DEVELOPMENT_TEAM: <Team ID>`. Raise `CURRENT_PROJECT_VERSION` for every upload (MARKETING_VERSION per release).
3. Create the app in App Store Connect (name, bundle id, SKU, primary language).
4. On a Mac: `xcodegen generate`, open `Ledger.xcodeproj`, Product, Archive, Distribute App, App Store Connect, Upload (or `xcodebuild archive` + `-exportArchive` with an export options plist, or `xcrun altool`/Transporter with an API key).
5. In App Store Connect, TestFlight: wait for processing, answer the export-compliance question (already declared no: `ITSAppUsesNonExemptEncryption = NO`), add internal testers (up to 100, no review) or an external group (first build needs Beta App Review, privacy policy URL and a contact).
6. Before public release also add: privacy policy URL, App Privacy answers (data not collected), age rating, screenshots (iPhone 6.9" and iPad 13"), description.

## C. What the owner must provide

- An Apple Developer Program account (99 USD a year) and its Team ID; for CI uploads an App Store Connect API key.
- The final bundle id (reverse-domain, e.g. `com.yourname.ledger`).
- The final app icon: 1024x1024 PNG, no transparency, no rounded corners (replace `AppIcon.png` and `icon-marketing-1024.png`, then regenerate the other sizes).
- A privacy policy URL, support URL, store texts and screenshots.
- A decision on the display name if "Ledger" is taken in the store.
