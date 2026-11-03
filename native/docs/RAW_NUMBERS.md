# Raw engine numbers in the UI

Helper: `Words.level(_ value:, scale:, of:)` and `Words.move(from, to, scale:)` in `App/Ledger/Design/Words.swift`. Scales: quality (Poor..Excellent), mood (Unhappy..Happy), condition (Worn out..Good).

## Fixed (file: before -> after)
- Design/Components.swift Meter: "63" next to bar -> word (scale parameter). Covers GroupOffice review score, equipment health, finance capital.
- Companies/CompanyFinanceBook: Capital meter fed 0-1 into a 0-100 meter -> scaled; "Solvency 0.72 needs 1.0" -> Critical/Too low/Adequate/Comfortable; "verified sellers 1.5" -> whole count.
- Companies/CompanyEquipment: "equipment health 63%" -> "equipment fair".
- Companies/CompanyOverview: "Quality 62" -> word.
- Companies/CompanyFranchise: "Quality 62 (brand minimum 55)" -> "Good (brand asks for good)".
- Companies/CompanyClub: "strength 54" sub-line removed (word already shown); "about +1.2 strength" -> "a small/solid/big boost to the squad".
- Companies/GivingView: "Standing 47 of 100" -> word.
- Reports/ReportsView: "Reputation 41 -> 47" -> "Fair" or "Fair to Good".
- Phone/ExpandAbroadView: "(31 of 35 needed)" -> removed.
- Phone/VenturesView: "relationship 62 of 100" -> word.
- Phone/GoalsView: "Legacy 1234" score line -> hidden.
- Engine ManagerPromotions review sheet: "Staff mood 63 / 100" -> Unhappy/Uneasy/Content/Happy; "Performance now 71" -> word; "Better since they started +6 points" -> Clearly better / A little better / No change.
- Engine SpecialEvents: "price index 1.07" -> "prices rise/ease".
- Engine KnobChange: "Quality: +3 points" -> "Higher/Lower quality".
- Engine RentalFinanceActions: "Solvency is 0.91; you need 1.0 ... 0.8" -> plain sentence.
- Engine FootballModel (sale offer): "about 3.0 strength points" -> removed.

## Kept (reason)
- Star ratings "4.2 / 5", "4.5 stars" (Reviews, suppliers, advisers, tenders): shown as stars in-world, a number the player knows.
- Percentages of money or share (margin, ownership, market share, vacancy, discounts, bids, odds of a deal, repaid, price vs list, loan share): player units.
- "x% of normal" energy/oil price and "points on last month" market share: percentage points of share, plain meaning.
- Contract "warnings N of 12": the limit is explained next to it.
- Fund "unit value" and "high-water mark": a price per unit, like a share price.
- Private equity / venture multiples "2.10x": multiple of money paid in.
- New company "size 1.5": the player's own choice in the stepper.
- Cohort numbers, invoice and reference numbers, week counts: ordinary labels.
- Rival pressure "takes 3% of demand": a share of demand the player's sales feel.
- Open follow-up: org-chart `level` (OrgNode) is layout only, not printed.
