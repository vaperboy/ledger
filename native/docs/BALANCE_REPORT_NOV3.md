# Balance report, 3 Nov: five years, baseline owner vs competent owner

Driver: `Tests/LedgerTests/BalanceReportProbe.swift` (skipped unless `LEDGER_REPORT=1`; `LEDGER_TRADES`, `LEDGER_SEEDS`, `LEDGER_YEARS`, `LEDGER_OUT`).
Run: 14 trades x seeds 11,12,13 x 2 owners x 5 years = 84 runs, all finished (UK, limited company, standard set-up, money in = estimate x 1.3 plus top-ups when cash < -50k).
Amounts in thousands of game units. Table values are means of the 3 seeds. Yearly series cover years 1-4 (the snapshot fires on the day before each year end; year 5 appears only in "final").
"Value" = `Valuation.companyValue`. ROI = mean profit years 2-4 / money in. "Money in" for the competent owner includes top-ups that paid the manager, so its ROI is understated for solo trades.

Owners:
- Baseline: quick set-up, nothing else (no manager, no ads, no items, premises proposals never reach him because only a manager proposes).
- Competent: modest ads (search, social, SEO at 2nd budget), hires a manager from week 4 when cash > 8 months of asking pay (pays 1.2x asking), adds 2 items (weeks 8 and 26), accepts every premises proposal, prices left at market (multiplier 1).

## Per trade (base = baseline, comp = competent)

| Trade | Owner | In | Value y1/y2/y3/y4 | Profit y1/y2/y3/y4 | ROI y2-4 | Final | Final/in | Bust | Staff y4 | Wages % rev y4 | Price-war wks |
|---|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| airline | base | 301453 | 253386/253184/230758/0 | -30157/-6401/-23144/0 | -4% | 0 | 0.00x | 3/3 | 17 | 14 | 0% |
| airline | comp | 284892 | 253386/366666/442616/582229 | -30157/30833/44060/71009 | 17% | 679863 | 2.39x | 0/3 | 34 | 14 | 1.1% |
| bakery | base | 3941 | 4828/9475/11895/13946 | 359/1662/1941/2123 | 48% | 12899 | 3.27x | 0/3 | 1.0 | 8 | 1.6% |
| bakery | comp | 3941 | 5983/8049/7421/8021 | 906/926/557/546 | 17% | 10890 | 2.76x | 0/3 | 6.7 | 30 | 0.9% |
| barber | base | 849 | 732/879/884/1088 | -125/191/43/260 | 19% | 1629 | 1.92x | 0/3 | 0 | 0 | 0% |
| barber | comp | 1937 | 256/351/260/264 | -668/-313/-251/-246 | -13% | 233 | 0.12x | 0/3 | 0.3 | 9 | 4.6% |
| carclean | base | 286 | 229/266/345/408 | 11/59/38/89 | 32% | 429 | 1.50x | 0/3 | 0 | 0 | 0% |
| carclean | comp | 914 | 410/242/482/204 | 91/-202/71/-432 | -20% | 490 | 0.54x | 0/3 | 0 | 0 | 3.2% |
| carrental | base | 2100 | 2532/2575/3310/3070 | 282/221/416/240 | 14% | 3434 | 1.64x | 0/3 | 0 | 0 | 0.9% |
| carrental | comp | 2758 | 1633/1751/2152/2181 | -459/-229/-37/-43 | 1% | 2135 | 0.77x | 0/3 | 1.7 | 25 | 0% |
| cons | base | 283 | 265/293/295/315 | -12/42/6/34 | 9% | 293 | 1.03x | 1/3 | 0 | 0 | 0% |
| cons | comp | 801 | 530/277/446/223 | 131/-242/-48/-224 | -15% | 385 | 0.48x | 0/3 | 0 | 0 | 2.1% |
| courier | base | 2611 | 3625/4248/3426/3049 | 618/235/-131/-47 | 1% | 3026 | 1.16x | 0/3 | 0.3 | 14 | 0% |
| courier | comp | 5058 | 2694/2580/1778/3559 | 97/-419/-1012/-481 | -5% | 2913 | 0.58x | 0/3 | 6.7 | 49 | 0.8% |
| factory | base | 45112 | 47482/44743/47153/52095 | 1163/-880/226/565 | 0% | 47809 | 1.06x | 0/3 | 2.7 | 13 | 10.8% |
| factory | comp | 45112 | 55246/70820/90641/92739 | 4975/6058/10067/8311 | 18% | 85916 | 1.90x | 0/3 | 13.7 | 19 | 1.0% |
| grocery | base | 16231 | 17849/22090/15276/12242 | 957/1138/-1469/-3000 | -6% | 8540 | 0.53x | 0/3 | 2.0 | 4 | 4.8% |
| grocery | comp | 19129 | 28957/40737/47534/46284 | 5669/4196/4447/3833 | 31% | 50430 | 2.64x | 0/3 | 14.3 | 6 | 0% |
| gym | base | 8316 | 8524/8397/8979/9117 | 193/7/294/224 | 2% | 9455 | 1.14x | 0/3 | 0 | 0 | 0.8% |
| gym | comp | 8316 | 10522/16632/17864/17717 | 1033/2046/1954/1531 | 22% | 17821 | 2.14x | 0/3 | 4.0 | 31 | 0.8% |
| hotel | base | 40073 | 41378/48408/46049/40893 | 305/2048/381/-1017 | 1% | 40237 | 1.00x | 0/3 | 1.3 | 8 | 9.3% |
| hotel | comp | 40073 | 43889/57811/70391/78852 | 1674/4315/6383/7706 | 15% | 81088 | 2.02x | 0/3 | 8.3 | 18 | 0% |
| restaurant | base | 6160 | 5370/6194/7539/9578 | -803/250/773/1179 | 12% | 9551 | 1.55x | 0/3 | 0 | 0 | 0% |
| restaurant | comp | 6160 | 8527/17428/22983/25894 | 1140/2878/3771/3825 | 57% | 29455 | 4.78x | 0/3 | 7.0 | 23 | 0% |
| tutor | base | 114 | 87/81/100/125 | -25/-5/3/30 | 3% | 80 | 0.70x | 1/3 | 0 | 0 | 0% |
| tutor | comp | 276 | 146/103/104/574 | 40/-84/-109/141 | 8% | 168 | 0.61x | 0/3 | 0 | 0 | 0.1% |
| webdev | base | 1378 | 1550/1752/1987/2254 | 224/279/306/371 | 23% | 2545 | 1.85x | 0/3 | 0 | 0 | 0% |
| webdev | comp | 2390 | 605/216/95/257 | -742/-563/-590/-61 | -15% | 297 | 0.12x | 0/3 | 0 | 0 | 0% |

Bankruptcy rate: baseline 5/42 (airline 3, cons 1, tutor 1); competent 0/42.
Headcount and wage share: staff y4 and wages as % of year revenue (monthly wage bill x 12 / revenue of the last 12 months). Grocery/hotel/factory stay at 4 to 19% of revenue; courier comp 49% and bakery comp 30% are the high ones.
Events (market log, all 84 runs): 27 to 37 entries a year per company; market-wide kinds 18 to 31 a year (about 0.35 to 0.6 a week); maximum market-wide in any one week = 1 in every run (the one-a-week cap holds).
Price reaction: wars/pressure weeks 0 to 10.8% of open weeks (worst: factory baseline 10.8%, hotel baseline 9.3%). Nothing near "most of the year".
Premises proposals accepted (competent only, first acceptance per run): 14 in 42 competent runs.

| Trade | Accepted (3 seeds) | Monthly revenue, mean of 3 months before -> 26 weeks after (units) |
|---|---:|---|
| airline | 1 | 17770->19910 (+12%) |
| barber | 4 | 131->173; 100->173; 131->155 (+18% to +73%) |
| courier | 3 | 471->495; 246->471; 274->567 (+5% to +107%) |
| grocery | 3 | 10067->10437; 5801->7799; 2756->8156 (+4% to +196%) |
| restaurant | 3 | 859->1265; 1010->1594; 1121->1485 (+32% to +58%) |

## Hiring spend (job ads + agency)

Measured 0 in all 84 runs. Reason: the scripted manager and the automatic hirers never buy a job ad or an agency (`JobAds.post`, `Agency.engage` are only called from the player actions in `HiringRebuildReads`), so this run did not exercise those costs. The detector (new `tx` entries labelled "Job ad" / "Agency") was not validated against a purchase, so 0 is "not exercised", not "proved small".
Analytic bound from the rules: agency fee 8% of the hired person's pay for 24 months <= 8% x wage share (max 49% courier, 31% gym) = at most 3.9% of revenue, plus one-off 8 x ad fee per agency search. Within the ~6% bound if only one agency hire per role is open; not simulated.

## Against previous expectations (BALANCE_REPORT.md and BalanceGuardTests)

Previous (3 years, hired-team column, standard set-up): bakery 12%, barber 15%, car rental 14%, courier 13%, factory 8%, gym 16%, hotel 11%, restaurant 6%, airline 6%, grocery 5%, cons 330%, tutor 99%, webdev 51%, carclean 212%.
Now, baseline owner (comparable): bakery 48% (high), barber 19%, car rental 14%, courier 1%, factory 0%, gym 2%, hotel 1%, restaurant 12%, grocery -6%, cons 9%, tutor 3%, webdev 23%, carclean 32%. Solo trades fell from hundreds of percent to 9 to 32% (marketing and the per-item/market changes); capital-heavy baseline trades sit at 0 to 2% (lower band edge).

`BalanceGuardTests` run on this head (336 s): 4 pass (NoTradeMakesYouRichQuickly, CapitalHeavyTradesEarnModestReturns, VehicleTradesOpen, HiredTeamWithoutOwnerHasCapacity), **1 fails: testAirlineAndShippingSurvive ("airline ended bust")**.

## Flags

| # | Flag | Evidence | Bound | Status |
|---|---|---|---|---|
| 1 | Airline never opens for a hands-off owner and goes bust | Trace (seed 12): checklist "Air operator certificate: In progress" for 48+ weeks, revenue 0, wage bill 1958k/month; baseline 3/3 bust. Competent owner (manager) opens and earns 17%. Also fails the existing guard | Guard: airline open after 3 years | OPEN, not a constant: opening paperwork stalls without a manager (or the harness never completes it). Needs an owner decision |
| 2 | Competent owner loses money in solo/small trades | barber -13%, carclean -20%, cons -15%, webdev -15%, tutor y2-y3 negative; manager wage on a 0 to 1 head business dwarfs profit (value falls to 0.12x to 0.54x of money in) | loss-making trade | OPEN, expected behaviour of the scripted policy, but a player doing this loses 50 to 90% of the stake: needs a UI warning, not a constant |
| 3 | Get-rich above 50% a year | restaurant comp 57% mean (seed 13: 82/83/107%), grocery comp seeds 11 and 13 at 44 to 81%, bakery base 48% | 50% a year | Restaurant comp only is above the line on average; grocery comp mean is 31%. Driver is stacked: manager + 2 items + ads + premises (grocery seed 13: monthly revenue 2756 -> 8156 after the move). Not changed: no single constant is clearly the cause |
| 4 | Role effects dominate | staffed trades gain +15 to +45 points of ROI with manager+items+ads (factory 0 -> 18, hotel 1 -> 15, gym 2 -> 22, restaurant 12 -> 57, grocery -6 -> 31) | n/a | Not separable in this run (all levers on together); no single lever isolated |
| 5 | Hiring cost > 6% of revenue | not exercised (0 measured) | 6% | Not measured; analytic max 3.9% on the agency fee |
| 6 | Market-wide events > 1 a week | max 1 in any week, 0.35 to 0.6 a week | 1 a week | OK |
| 7 | Price-reaction wars most of the year | max 10.8% of open weeks (factory base) | most of year | OK |
| 8 | Capital-heavy baseline near zero | factory 0%, hotel 1%, gym 2%, courier 1% | median 2 to 20% | Edge; the guard median still passes |

## Recommended tweaks (none applied)

| Item | Suggestion | Why not applied |
|---|---|---|
| Airline opening | complete the AOC step for a company without a manager (or have the harness do it) | not a single constant; behaviour/design |
| Manager in a solo trade | warn or refuse a manager hire when headcount is 0 or 1 (wage > 40% of monthly profit) | design, not a constant |
| Premises move uplift | `PremisesProposals.marginKept` 0.85 -> 0.7 and `minUnmetShare` 0.05 -> 0.10 would damp the x3 jump on tiny start premises | no bound clearly crossed (grocery mean 31%); needs the guard re-run (about 5 min) |
| Restaurant | none until flag 3 is reproduced with fewer stacked levers | |

## Runs

Finished: 84 of 84 report runs (14 trades x 3 seeds x 2 owners x 5 years); BalanceGuardTests (5 tests, one failing: airline); MoneyLiteralLintTests (pass).
Not run: BalanceProbeTests env probes (LEDGER_BALANCE all 50 trades), Stage10ReconciliationTests, DeterminismSavesDatesTests (no tweak was made, so not required).

## Restaurant congestion (4 Nov)
Added congestion cost (venue and svc trades, utilisation above 0.85, 0.18 of weekly payroll at full utilisation, plus up to 5 quality points). Probe seeds 11/12/13, 5 years, mean ROI per year: restaurant competent 59% before, 40% after (0.12 of sales gave 37% and broke grocery; 0.3 of payroll gave 31%). Restaurant baseline 5% to 3%; grocery unchanged (32% competent, -4% baseline); barber 20% to 16% baseline, carclean 22% to 27% baseline (random-draw noise).
