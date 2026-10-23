# Deal of the week (`dow56go`, state `dow56`, `dow56n`, `reb56`, rival flag `dow56`)

Doc references: native/docs/SCREEN_MIGRATION_INVENTORY.md:40 and :59 list it as a "missing original system" in the port order. PARITY_CHECKLIST.md:486 marks the action `dow56go` "Presentation only"; :969 and :1742 list step 92 and the `proposeBuy.terms` hook. native/docs/DESIGN_RULES.md read (one home per feature; actions with cost, benefit, risk, timing shown before confirming; no game rules in views).

## 1. What the original does, and what Swift has

Original (orig/.../features/player/goals_and_awards.js, "GA56"). It is NOT a supplier or stock deal. It is a personal-wealth and acquisition nudge shown as one row on the Group tab (ui/screens/group_tab.js:29, via `GA56.dealRow`).
- Cadence: one deal, open 7 days (`exp = week + 1`, :60). After it ends the next is due `week + 2 + floor(Z()*4)` weeks later (:81). Step `week.after` order 92 (:78-85). Header comment :43-46.
- Three kinds, picked uniformly among those that qualify (:48-60):
  - `riv`: a rival owner of one of your open non-finance/energy/club/holding/rent companies (first 3 rivals, not locked) sells at ask = 80% of `rivalValue`, only if cash covers ask + KC(200000) (:49-52, :62-64). Sets `r.listed = true; r.dow56 = exp`. The `proposeBuy.terms` hook (:87) multiplies the owner's willingness by 1.25 ("takes about 20% less") while the deal is open.
  - `lux`: one luxury item with price <= 40% of cash (not estates), 15% off via `GA.luxOff` (:88). Note `luxOff` is exported but I found no caller outside this file (grep of orig/ for `luxOff` only hits :88), so the 15% may never be applied in the original: UNVERIFIED which caller would use it, and the row's "-15%" may be a promise the buy screen does not honour.
  - `stock`: a held-universe share (only offered if you own some stocks and cash > K(100000), :55-56) is knocked down 12% (`x.p *= 0.88`), and `reb56` nudges it +2% a week back toward its old price for up to 10 weeks (:62, :82).
- Gate: row hidden unless cash >= `dealCost` (:89-91). Rival/lux are handled by opening the normal screens (`ACT.dow56go`, :93). No cost, risk or expiry confirm of its own.
- Who can use it: any player with cash and at least one qualifying object; scale-free (all costs are thresholds on cash).

Swift today: nothing. `grep dow56|keen seller|reb56|luxOff` in native/Engine/Sources finds no implementation. The step ordering has no step 92.

## 2. Does the current game already cover the gap?

What the three kinds buy the player, and the existing Swift equivalent:

| Original kind | Swift equivalent |
|---|---|
| Rival sells ~20% under value | Rivals.proposeBuy (Businesses/Rivals.swift:735-760) already has a `listed` state: listed owners accept `need` 0.95 vs 1.55 (:742, :757). Weekly rivals roll flips `listed` on at 3%/wk and off at 12%/wk (Rivals.swift:481); big rivals can be listed by random event (:337). Troubled rival groups multiply willingness x1.45 (:747). Aftermath chain 10 "distressed" (Events/Aftermath.swift:18, :32, queued :72) is a decision with Pass / small offer (50% gamble, +12% demand 10 wk) / buy customers+stock (-3 weeks sales, needs capacity). Also the Luxury "serious buyer" perk, `Luxury.offerBonus`, and hosted owners (`StaffPerks.rivalFactor`) improve offers. So the "motivated seller" idea exists three ways (listed flag, group in trouble, distressed event). |
| 15% off a luxury item | Luxury.buy(itemID:, price:) already takes a price (Businesses/Luxury.swift:100). Luxury is a wealth sink, with upkeep (:90) and depreciation (:268); a coupon on it rewards spending, not building. Weak purpose. |
| Share fell 12% and drifts back | Investments/Markets.swift:63-82 already has regimes (bull/correction/bear/recovery/crash at 3%/wk, drift -4%/wk, "MARKETS PANIC" news :78). A recovery regime is a real, un-scripted buy-the-dip. The deal's 12% overshoot with a scripted +2%/wk rebound is a near-guaranteed ~10-20% profit on cash (risk-free arbitrage) if the rebound is kept; without it, it is just a price cut. |

Supplier discounts/stock (the thing the owner asked me to compare) are a different problem: Suppliers.discount = relationship tier + 3% board agreement (Businesses/Suppliers.swift:123-127; `agree` costs 9000 home-scaled, :131-142; `meet` :97; goods vendors :163-185). Used equipment: EquipmentMarket.usedEquipment/usedVehicles (:385, :410) with hidden truth (:376) and `buyUsed` (:537). Event opportunities: Aftermath `bulk` standing deal (chain 11) and `premises` offer (chain 12), `negotiate` fixed-price contract (:~17 chain 6). Tenders: ProjectTenders, VolumeTenders (Businesses/VolumeTenders.swift), key accounts (Businesses/KeyAccounts.swift:24 max by reputation). None of these is what the original deal is, and a weekly "discount on goods/equipment" would duplicate them (supplier relationship is already a standing discount; used market already a discount-with-risk; bulk/negotiate already a decision with deposit vs 26-week lock).

Gameplay purpose of the original: a soft "something to spend idle cash on this week" prompt, so a player sitting on cash is nudged toward acquisitions, luxury or stocks. Value to a small owner-operator: low (rarely meets the cash gates, and kind selection is cash-threshold based). Value to a 10-store group: also low; they already have Advisor suggestions (Simulation/Advisor.swift:37, "opportunities" last), acquisitions screens and a stock tab. The only thing it gives that Swift lacks is a time limit (7 days) and a visible "save X" figure.

## 3. Decision test: does a weekly deal add a real decision?

- Timing: Aftermath events already carry expiry (`exp` weeks, e.g. distressed exp 3). Adding another with 7-day expiry adds no new axis.
- Cash vs working capital: the interesting trade-off (spend cash now vs keep for payroll/stock) is the standard one every offer already poses. The original removes it by hiding the row unless cash >= cost, i.e. it never forces a trade-off.
- Risk: none in the original (no risk shown, stock rebound is scripted). A genuine-risk version would just be the distressed event or the used-equipment market again.
- Exploit surface if ported as-is: (a) stock kind = guaranteed rebound = free money (also `reb56` mutates prices outside the Markets weekly random walk and golden tests); (b) rival kind sets `listed = true` and a x1.25 offer multiplier: repeated every 2-5 weeks it is an always-reachable discount on acquisitions; (c) lux kind is a coupon on a depreciating asset; (d) `S.dow56n` timing is predictable, so players can hoard cash for it. Each touches RNG (`Z()` in original; Swift would need a new HashedRandom stream) and the week-after step order, so golden/differential tests (BALANCE_PARITY, month-end ordering) would need new keys.
- Duplicates: yes, for all three kinds (table in section 2).

## 4. Data and save impact (if it were built anyway)

New rest keys `dow` (current deal object or null) and `down` (next-deal week, default 0); rival JSON `dow` expiry; stock rebound list `reb`. All default-safe (missing = none). UI home would be the Inbox tab (DESIGN_RULES: offers/decisions live there), not the Group tab. Not needed.

## 5. RECOMMENDATION: REMOVE

Reason: it has no clear role in the current economy and it is a copy of mechanics the Swift game already has in richer, riskier form:
- Motivated seller: `Rivals` listed flag + troubled group multiplier + Aftermath `distressed` decision.
- Dip buying: Markets regimes incl. crash/recovery (Investments/Markets.swift:63-82), un-scripted.
- Supplier/equipment savings: Suppliers relationship tiers and board agreement, used equipment market, `bulk` and `negotiate` aftermath decisions, tenders and key accounts.
- Luxury discount: no purpose beyond a coupon.

Actions: tick it off in SCREEN_MIGRATION_INVENTORY.md (lines 40 and 59, port-order item 4) and PARITY_CHECKLIST (:486, :969, :1742) as "intentionally not ported, covered by Rivals listed state, Aftermath distressed/bulk/negotiate, Markets regimes, Suppliers". No engine change, no tests, effort S (docs only).

Optional small ADAPT if the owner wants a visible nudge for idle cash (otherwise skip): do not add a new deal system. Instead let Advisor.swift (:37) rank an "opportunity" row when a rival of an owned company has `listed == true` (Rivals.swift:481) and cash covers the likely price, linking to the existing offer screen. Effort S, depends on nothing, no new state, no exploit (no price change, no RNG), and uses the Inbox/Advisor primary home. If the owner instead insists on a true deal, minimum safe format: an Aftermath-style data event (cost, benefit, risk, expiry 1-3 weeks as in Events/Aftermath.swift templates) offering a rival buy-out whose discount is paid for by risk (hidden liabilities, as used equipment has), with a cooldown and no stock kind; effort M, depends on Aftermath queue and Rivals.proposeBuy; I do not recommend it.

Unchecked: the original UI path that applies `luxOff` (UNVERIFIED, grep found no caller); Swift stock price storage format beyond `rest["stocks"]` (UNVERIFIED, only read Markets.swift header and weekly head).
