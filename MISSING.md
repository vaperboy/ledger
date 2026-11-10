# Still to do

## Engine
- Supply is billed on the server's real-time market week (Monday UTC), not per game week of each company.
- XP farming: repeated small loans still feed Season and ladder XP; needs a cap or cooldown.
- Playtest thresholds (bot invariants) and Ladder tuning are unverified; the long balance probes are skipped in CI.
- Engine actions with no screen yet: location proposals and premises-move offers from managers, supplier stop and contract end for player suppliers, supplier delivery record and block, executive courses and office-role results, performance-analyst auto switch, own adviser firms, accountant choices, rebrand cost, draft-invoice send, bid preview, customer discount end, dealer policies, staff perk cover and story, market competitors and city profile, start estimate, government admin list.
- Engine reads tested but not used by any screen: exchange order, listing and dividend previews, setup funding, sourcing contracts, team search.
- Gold purchases and bundles in the Store are a mock; an AltStore build cannot buy.
- Ads run on a placeholder provider; the AdMob packages and Info.plist keys are not added.

## UI/UX
- Expand abroad, Insurance, Atlas and Weather have no fallback when the week data is missing (first week, new company).
- The Country app stays hidden until the player is a level away from unlocking it.
- Accountant leaderboard and rating: the server call for rating a hire exists in the client, no screen uses it.
- Block list: the client call exists, no screen shows blocked players.
- Sign out in Settings only pauses the online session until the next launch or "Go online"; the anonymous server account stays in the Keychain, so a lost session means a new empty account.
- Restoring a linked account on a new device is not possible: linking a Google account that already belongs to another player is refused and there is no sign-in-to-existing-account flow.
- UI feature tours and popup screenshots run only by hand (workflow `native-tours`, `native-ios` screenshot job); keep them in step with new screens.
- English text only; no localisation files.

## Assets
- Pictures drawn in code: trades, artifacts, themes, backdrops, name plates, trade plates, flair, boxes, badges, advisors, save slots, gold and avatars are SF Symbol emblems on gradients. Real pictures go in `Assets.xcassets/Art/<folder>/art.<category>.<id>.imageset` and are picked up with no code change.
- Photos exist only for AirStay (offices, shops, stores) and TechPro (van, pickup, car, premium); other outside apps have none.
- App icon is a placeholder drawn by script; no store screenshots (`screenshotURLs` in `apps.json` is empty).
- Sounds are seven system sounds only; no own sound effects or music.
- The five art sheets (premises, luxury, cars, logos, trophies) were removed after slicing; the cells remain, the sheets are in git history.
- Bundle id and source identifier are `com.example.*` and must change before App Store submission.

## Server
- `OnlineConfig.useServer` is true: every player gets an anonymous server account at first launch. The stand-in service stays for offline mode and for the markets, joint ventures and startup market that have no server client yet.
- Google linking needs the dashboard: enable the Google provider (client id and secret), switch on manual linking, check anonymous sign-ins are on, and add `ledger://auth-callback` to the redirect URLs. Until then the link button shows a friendly "not set up yet" message.
- Apple linking is hidden: Sign in with Apple needs a capability a sideloaded build does not have. The web flow needs a paid developer team with a Services ID; then add `.apple` to `OnlineConfig.serverLinkProviders`.
- Swift clients missing for supply market, startup market, joint ventures, player deals, exchange positions, trade associations, store and auctions (all mock). Clients exist for profiles and friends, admin, leaderboard, accountant offices, world rules and news.
- Migrations 0001 to 0021 are applied to the live project; `0022_anonymous_players.sql` (anonymous players may create a profile and read their status) must be applied by SQL until the `SUPABASE_DB_PASSWORD` repository secret is set (the workflow also reads `SUPABASE_ACCESS_TOKEN`).
- The `invite` edge function needs deploying; `supabase/seed.sql` is dev data only.
- SQL tests run only from the manual `supabase-migrate` workflow.
- TestFlight upload needs the App Store Connect secrets (`APPLE_TEAM_ID`, `IOS_BUNDLE_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`).
