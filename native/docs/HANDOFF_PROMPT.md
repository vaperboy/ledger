# Handoff prompt (paste this whole file into a new Claude Code session with access to vaperboy/ledger)

You continue the native SwiftUI **Ledger** business simulation. Repo `vaperboy/ledger`, live branch `native-swiftui` (engine `native/Engine`, app `native/App/Ledger`, docs `native/docs`). Read first, in order: `native/docs/MASTER_SPEC.md` (the owner's 10-stage spec), `native/docs/DECISIONS.md` (every owner decision, newest last: binding), `SIMULATION_RULES.md`, `DESIGN_RULES.md`, `native/docs/MASTER_AUDIT.md`, `native/docs/HANDS_ON_TEST_PLAN.md`, `KNOWN_GAPS.md`. Never delete anything without explicit owner approval.

## How the owner wants you to work (RULES)
- **Minimise usage**: no re-reading files you already have, no full rewrites (use small edits), no exploratory sweeps, no big reports. Prefer grep to reading whole files. Agents: max two at a time, local commits only, never push; give them exact scope and a short report format.
- **Test on CI only, and only engine-tests + app-build.** No screenshots, no unsigned-IPA run (both removed). Read only whether `app-build` failed (and the `error:` lines if it did). The owner tests on the phone.
- A green app-build on a push to native-swiftui publishes the AltStore build automatically (see Release flow). Update `RELEASE_NOTES.md` before pushing code.
- Short, to-the-point answers; report only verified results; no "unverified/not done" leftover lists: raise real decisions with AskUserQuestion (up to 4 options, recommended first) plus PushNotification.
- Fewer, bigger pushes (each CI run is slow and rate-limited). Cancel duplicate `pull_request` runs. Pull (`git pull --no-rebase`) before pushing: a bot commit updates apps.json.
- App compiles only on macOS CI; engine tests run on Linux (`/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin`, `swift test --skip BalanceProbe`, ~30 min, run in background). Compile discipline: grep every call against the current definition, exhaustive switches, public engine access, ViewBuilder <= 10 children, split long expressions, avoid names clashing with SwiftUI/Foundation, no digit `\u{...}` escapes, no `.buttonStyle(.plain)` (use PressableStyle), never make engine types Identifiable from the app (wrap them).
- Never delete anything without explicit owner approval. Every owner decision goes into `native/docs/DECISIONS.md` (binding).

## Release flow (changed 2 Nov: automatic)
Owner rule: only read `app-build` (fail or not); screenshots are removed (the owner tests on the phone) and there is no separate unsigned-IPA build. `.github/workflows/native-ios.yml` has jobs engine-tests (evidence), app-build, and `release`: on a push to native-swiftui touching `native/**` (not `native/docs/**` or `native/design/**`) with app-build green, it builds the unsigned IPA, creates Release `v<N>` and a bot commit updates `apps.json` (N = latest apps.json version + 1). So BEFORE pushing code: update root `RELEASE_NOTES.md` (short "What's new / Missing"); after the bot commit run `git pull --no-rebase` before your next push. Docs-only pushes do not build. Cancel stray `pull_request` runs. `native-ipa.yml` (push to `ipa-build`) stays as a manual fallback only. AltStore source: https://raw.githubusercontent.com/vaperboy/ledger/native-swiftui/apps.json. `gh` works via REST only.

## State right now (2 Nov 2026)
- `native-swiftui` contains everything merged: Stages 1-8, the popup/button system, Phone apps AirStay / TechPro Store / Atlas Insurance, Stage 4 (cap table, budgeted creation, startups as companies, rival acquisition, expansion form) with the owner answers (month of rent and instalments held back, support hire in founding team, accountant + registration at founding, right of first refusal on stake sales). The merge of the three branches was NOT compile-reviewed (the reviewer hit the usage limit): if `app-build` fails, fix the `error:` lines from the job log (`gh api repos/vaperboy/ledger/actions/jobs/<id>/logs | grep "error:"`), push again.
- Local worktree branches `work-confirm`, `apps`, `stage4` are already merged; they can be ignored.
- Owner's to-do for you right after the build is green: build the own-delivery fee (logistics company books a delivery fee as revenue, buyer pays it).

## Owner decisions that shape the rest (all in DECISIONS.md)
Popup only for spends above "Ask before spending" (default step 2) and irreversible actions, everything else applies at once; Inbox follows the same rule. Premises+Where you work = AirStay; Equipment+Software = TechPro; Insurance = Atlas (all Phone apps with reference pictures in `native/design/mockups/`). Button/popup look from `button_popup_system.jpg` at phone sizes (not wide). Icons per `icons_moodboard.jpg`. Photos under `mockups/photos/`.

## Remaining work, in order
1. Get app-build green on the merged state (fix errors), confirm the new version in `apps.json`.
2. Own-delivery fee (above). Then Stage 5 remainder: typed prices with per-trade range from data, suppliers recorded in Accounting, chain/franchise application steps with real requirements and review time.
3. Owner will test the build on the phone and report; fix what they report first.
4. Stage 9 release cleanup: exclude the 5 art sheets from the release build, disable `main.yml`/`yesmain.yml` (keep the files); any deletion needs owner approval.
5. Stage 10 regression: full engine suite, hands-on test plan rows (NOT TESTED), open audits (balance audit, calculations parts 2-4, wage-share, shipping guard, 22% auto-hire volume drop).
6. Unanswered owner questions: top-level Team tab duplicate tabs (Overview and Delegation); deletion of unused `BoardsGroupSection`; ambition as an Overview mission link.
