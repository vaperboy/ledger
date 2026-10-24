# Getting the app onto your phone with TestFlight

I (the assistant) cannot create Apple accounts, keys or secrets. These steps are yours; the build and upload are automated by `.github/workflows/native-testflight.yml`. The upload has NOT been run yet: it needs your secrets, so the first run may need fixes.

## One-time setup (about 30 minutes)
1. **Apple Developer Program** membership (paid, yearly). Note your **Team ID** (developer.apple.com > Membership).
2. **App Store Connect** (appstoreconnect.apple.com) > Apps > + New App: platform iOS, name Ledger, pick a **bundle ID** you own (for example `com.yourname.ledger`; register it under Certificates, Identifiers & Profiles > Identifiers first), any SKU.
3. **API key**: App Store Connect > Users and Access > Integrations > App Store Connect API > generate a key with role *App Manager*. Download the `.p8` once. Note the **Key ID** and the **Issuer ID**.
4. In GitHub: repository Settings > Secrets and variables > Actions > New repository secret, five secrets:
   - `APPLE_TEAM_ID` the Team ID
   - `IOS_BUNDLE_ID` the bundle ID from step 2
   - `ASC_KEY_ID` the Key ID
   - `ASC_ISSUER_ID` the Issuer ID
   - `ASC_KEY_P8_BASE64` the `.p8` file, base64 encoded (`base64 -i AuthKey_XXXX.p8 | pbcopy` on a Mac)
5. In App Store Connect > your app > TestFlight, add yourself as an **internal tester** (your Apple ID must be on the team).

## Each build
GitHub > Actions > "Native iOS TestFlight upload" > Run workflow (default branch `native-swiftui`). When it finishes, App Store Connect processes the build (10 to 30 minutes), then the TestFlight app on your phone offers it. The build number is the workflow run number.

## Known limits
- The app icon is a plain placeholder (gold L on dark) so uploads validate; replace `AppIcon.png` when you have a real one.
- Saves from the old Capacitor app cannot be read (see KNOWN_GAPS.md).
- The App Store privacy questions: the app collects nothing and has no network access.
