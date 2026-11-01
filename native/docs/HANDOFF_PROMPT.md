# Handoff prompt (paste this whole file into a new Claude Code session with access to vaperboy/ledger)

You continue the native SwiftUI **Ledger** business simulation. Repo `vaperboy/ledger`, live branch `native-swiftui` (engine `native/Engine`, app `native/App/Ledger`, docs `native/docs`). Read first, in order: `native/docs/MASTER_SPEC.md` (the owner's 10-stage spec), `native/docs/DECISIONS.md` (every owner decision, newest last: binding), `SIMULATION_RULES.md`, `DESIGN_RULES.md`, `native/docs/MASTER_AUDIT.md`, `native/docs/HANDS_ON_TEST_PLAN.md`, `KNOWN_GAPS.md`. Never delete anything without explicit owner approval.

## How the owner wants you to work
- Short, to-the-point answers; report only verified results. No "unverified / not done" leftover lists: raise real decisions with AskUserQuestion (up to 4 options, recommended first) and a PushNotification.
- Fewer, bigger pushes (CI is rate-limited; a full run takes ~50 min). Agents commit LOCALLY and never push; you integrate once per milestone after a compile review, then push. Max two agents at a time. Do not idle because CI is queued.
- Docs-only pushes and the duplicate `pull_request` runs waste CI: cancel the duplicates (`gh run cancel <id>`), push docs with code.
- The app can only be compiled on macOS CI. Linux Swift 6.0.3 (`/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin`) runs engine tests (`swift test --skip BalanceProbe`, ~30 min). Compile discipline: grep every call against the current definition, exhaustive switches, public engine access, ViewBuilder <= 10 children, split long expressions, avoid names that clash with SwiftUI/Foundation, no digit `\u{...}` escapes (money-literal lint), no `.buttonStyle(.plain)` (use PressableStyle), never make engine types Identifiable from the app (wrap them).
- Nothing goes to AltStore unless `engine-tests` AND `app-build` are green on that commit (screenshot jobs are evidence, not a gate).

## Release flow
Update root `RELEASE_NOTES.md` (short "What's new / Missing"), then `git push origin origin/native-swiftui:ipa-build --force`. That runs `.github/workflows/native-ipa.yml`: builds the unsigned IPA, stamps version 1.0.<run>, creates Release `v<run>`, and a bot commit updates `apps.json` on native-swiftui (so `git pull --no-rebase` before your next push). Cancel any stray `pull_request` "Native iOS" run on ipa-build. AltStore source: https://raw.githubusercontent.com/vaperboy/ledger/native-swiftui/apps.json. Current published: 1.0.10 (Stages 1-3, 6, 7, 8). `gh` works via REST only (no GraphQL; remote branch deletion and release editing are blocked, the owner deletes old branches by hand).

## State right now
- native-swiftui (pushed): everything up to Stages 7+8 plus docs and the UI-test fix (ambition popup dismissed). CI run 41341019648 was in progress (engine-tests, screenshots); app-build and ipa green.
- Local branches in `/home/user/ledger` (worktrees under `.claude/worktrees/`), commits NOT pushed, awaiting integration:
  1. `work-confirm` (3734444): in-game "Are you sure" popup (`Design/GamePopup.swift`, `ConfirmPopup`, engine `ConfirmRule`) replacing every iOS confirmationDialog; Inbox small answers apply at once; Perks popup; Rules box moved to Stats; Statements removed from Manage; Owed/Money matters titles removed; Your time read-only; supplier boxes; button system (`Design/ButtonSystem.swift`).
  2. `apps` (bc58896, based on work-confirm): Phone apps AirStay (premises + where you work merged, rent flow, active rents), TechPro Store (equipment + software merged, basket, checkout, delivery days, autofill, remember me), Atlas Insurance (coverage UI moved), engine delivery days / receipts / rent assignment / policy numbers, icon style.
  3. `stage4` (0648838): Stage 4 (cap table with integer shares, budgeted business creation plan, startups as real companies, expansion form, rival acquisition transfer) plus the owner answers (hold back a month of rent and instalments before any hire; first support hire in the founding team; accountant and registration fee at founding; right of first refusal on a holder's stake sale).
- Integration plan: merge `apps` (contains work-confirm) and `stage4` into native-swiftui, resolve conflicts (DECISIONS.md, HANDS_ON_TEST_PLAN.md: keep both sides), run a pre-push compile review (an agent that greps every changed call against definitions), run the engine tests, push once, wait for engine-tests + app-build green, fix compile errors from the CI logs (`gh api repos/vaperboy/ledger/actions/jobs/<id>/logs | grep "error:"`), then release.
- Agent logic note: if stage4/apps agents are still running, resume them with SendMessage instead of starting duplicates; check `git -C <worktree> log`.

## Owner decisions that shape the rest (all in DECISIONS.md)
Popup only for spends above "Ask before spending" (default step 2) and irreversible actions, everything else applies at once; Inbox follows the same rule. Premises+Where you work = AirStay; Equipment+Software = TechPro; Insurance = Atlas (all Phone apps with reference pictures in `native/design/mockups/`). Button/popup look from `button_popup_system.jpg` at phone sizes (not wide). Icons per `icons_moodboard.jpg`. Photos under `mockups/photos/`.

## Remaining work, in order
1. Integrate the three local branches (above), CI green, release (update RELEASE_NOTES.md).
2. Stage 5 remainder: typed prices with per-trade range from data, suppliers recorded in Accounting, chain/franchise application steps with real requirements and review time.
3. Screenshot-driven one-screen-overview pass (look at CI screenshot artifacts of the three jobs, fix design rule violations).
4. Stage 9 release cleanup: exclude the 5 art sheets from the release build, disable `main.yml`/`yesmain.yml` (keep the files); any deletion needs owner approval.
5. Stage 10 regression: full engine suite, hands-on test plan rows (all NOT TESTED), audits still open (balance audit, calculations parts 2-4, wage-share, shipping guard, 22% auto-hire volume drop).
6. Owner questions still unanswered: top-level Team tab duplicate tabs (Overview and Delegation); deletion of unused `BoardsGroupSection`; ambition as an Overview mission link (no mission record exists).
