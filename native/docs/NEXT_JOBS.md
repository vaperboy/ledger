# Next jobs (written 27 Oct 2026, to start when usage resets)

Owner direction. Do not start before the CI screenshot review of run 40493349153 is done. Every screen is designed individually (see DESIGN_RULES top rule). Inspiration images (feel only, not to copy): `native/design/inspiration-2026-10/`.

## A. Fewer sub-menus: tables that open forms (all company tabs)
1. Tabs like Operations stop using many small sub-tabs (Setup / How you sell / Marketing / Premises / More). One page per tab: key figures above, a table of settings in the middle, key figures or warnings below.
2. Each table row = one setting with its current value. Tap: a simple popup/sheet for a small change (price slider, hours, maintenance level); a full-screen page for a bigger decision (premises, suppliers, ways to sell).
3. Apply the same pattern to Finances, Team, Marketing, Properties, More. Keep the top-level tab names the owner approved; remove only the second row of sub-tabs where a table can replace it.
4. Per-screen design stays individual: own layout, own graphs and icons. No generic template.
5. Check on screenshots; fix only the files that fail.

## B. Bank app becomes the one place for all money (feel: the four inspiration images)
1. Bank home: pick an account (personal, each company) as now; balance hero with allocation ring (like the investment ring image) where it makes sense; round action buttons (Deposit, Send, Transfer).
2. Bills: every company's upcoming bills in one list, each with Pay now (early payment already exists in the engine: `payObligationNow`). Rows run by a manager or accountant say so. Payroll alert bubble stays.
3. Investments inside Bank: portfolio ring + assets list with small trend lines; Buy / Sell as full flows (amount, duration/term picker, recommended option highlighted, summary, confirm). Use the existing `InvestView` engine calls, no new rules in views.
4. Loans inside the account: apply flow in three steps like the loan images: (a) amount + term slider + payment day, (b) agreement text with checkbox, download not needed, (c) summary (amount, fee, disbursal, repayment, rate, EMI, first payment). The engine must produce the real quote, fee and instalment; the views only show it. Fake document filling: a forms step (name, income proof, company papers) whose answers the engine can use or check; report engine's real result.
5. Taxes, VAT, statements, savings stay in Bank; Group has no finance tab.
6. Engine first: loan quote read (fee, EMI, schedule), application action with documents, then screens.

## C. Weather becomes its own phone app
1. New Phone app "Weather" imitating a real weather app: current conditions for the player's city, hourly and daily forecast (engine already has `Glyph.weather`, forecast reads used by News), city switcher for companies abroad.
2. Own notifications: bubble on the app icon and a banner on the phone home when something big is coming (storm, heatwave, flood) with which companies it affects.
3. Remove weather from News completely, no link left in News. Engine read for "big event warning" and its effect on companies; tests.

## D. After A–C
1. One build, screenshots, review ~10 key screens, one batch of fixes.
2. Find and fix the UI tour timeout (iPhone/iPad tour fails after ~14 min).
3. Then the planned long balancing/testing pass (it also tests that the UI is wired).

## E. Owner additions (27 Oct 2026, later) - wait for the owner's go before starting
1. Weather: no link inside News at all (the Weather app is reached from the Phone home only).
2. Screenshots: a new run must not leave old pictures in the `ui-shots-*` branches. The workflow publishes with a fresh `git init` and force push, so old files should already be gone; verify. If any old file can remain, put the run's commit short sha and time in every file name (or a visible NEW marker) so new pictures are identifiable.
3. Phone app icons get colours: each app on the Phone home has its own colour inside the icon (not all champagne), still inside the Ivory Ledger palette and the dark style (muted, harmonious tints, never loud). Colour never alone: keep the glyph and label.

## F. Images and icons for things (owner, 27 Oct 2026) - wait for go
Premises, managers, workers, companies and luxury items will get their own icons or pictures. Before art arrives:
1. Check what exists: is there an image/icon slot on premises, people (PersonCard), company rows and luxury items? Add a small shared `ThumbnailView` (picture if the asset exists, otherwise the current icon circle) so art can be dropped in later without touching layouts again.
2. Re-plan the menu layouts that must show them: Premises table rows, People cards, Company rows on Home and Group, Luxury grid and item sheet, Hiring/candidate cards. Leave room for a square or round thumbnail; keep text readable, no reflow when art is missing.
3. Owner will supply the art and the order; names of asset files decided then (asset catalogue, one set per kind: premises, person role, trade/company, luxury item).

## G. Reusable overview layout (owner, 27 Oct 2026) - image: native/design/inspiration-2026-10/overview-table-layout.jpg
Ignore its words and colours; the LAYOUT is the pattern for tabs: (1) one or two hero cards with the key figures and a change vs before; (2) an overview TABLE inside one bordered card: a small icon circle per row, name, value, and a coloured change (arrow + %), with a period menu (e.g. 12 months) top right; rows open a popup (simple) or a full page (big); (3) a row of 3-4 count tiles (e.g. structure counts) with 'View all'; (4) a latest-activity list with icon, title, subtitle, chevron. Pill-style sub-menus (Summary / Bank / Invest / Taxes) are allowed under a top tab when a tab truly has separate parts, but keep them few. Build as shared pieces (OverviewTable, CountTiles, ActivityList) and use them across tabs, each screen still with its own content, charts and icons (never an identical copy). Apply first to Group Overview/Finances-like views, company Finances/Operations summary, Team overview, Projects.
Owner clarification (G): the same table is also the 'View all' target and the way into sub-areas: every row (and every count tile) is clickable and opens that sub-area (popup for simple, full page for big), so the table replaces the sub-menu row instead of sitting next to it. 'View all' opens the same table in full, with every row.
