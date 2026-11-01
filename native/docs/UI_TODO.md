# UI to do (engine is ready, no screen yet)

Placement follows the grouping rules in DESIGN_RULES.md: Company = one company, Team = people, Group = across companies and owners, Projects = jobs and ventures, Inbox = things waiting on the owner.

| Engine API (`GameEngine`) | Where it belongs |
|---|---|
| `claimedExperienceYears(personID:)` | Company > Team > hiring candidate row: "Claims N years" |
| `lastDividendDecision(companyID:)` | Group > Owners > dividend policy: last quarter's decision (paid / skipped, profit) |
| `groupTaxContribution(companyID:)` | Group > Money > group tax: this year against last year |
| `payrollOverview(companyID:).wageShortfall` | Company > Team > Payroll, the late-payroll banner: what is still unpaid |
| `runLatePayrollNow(companyID:)` | Company > Team > Payroll, button on the late banner (also answerable from the Inbox) |
| `ambitionPerk(path:)` | Goals card: the perk text beside each milestone |
| `canRaiseFunding(companyID:)`, `weeksUntilNextPitch(companyID:)` | Projects > Ventures > startup product: enable the pitch button, say when the next one is possible |
| `moveHomeQuote(companyID:)` | Company > Premises: confirmation sheet before moving a home-based company back |
| `toggleKnobOption` / insurance `togglePolicy` | no change; the owner's own policy choice is now respected by the assistant (`insOwn`) |
| Read-only screens: monthly results, rival of the month, business paper, weather and tourists, crisis centre, retirement hall | Phone > World around you / Stats (see MISSING_ACTIONS.md) |
