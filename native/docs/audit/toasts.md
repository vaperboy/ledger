# Toast and confirmation audit (`store.show`)

Scope: every `store.show(` call in `native/App` (453 calls in 52 files).

Method: grepped all calls. Calls whose text is chosen by a ternary, `switch`, `if ok` or an engine result were treated as result-dependent and spot-checked. The 68 calls with no visible condition were each read; the ones that announced success without an engine result were fixed (below). Setting-style engine actions now return `SettingResult` (`applied`, `unchanged`, `refused(reason)`) and the app reports it through `GameStore.settle`. A separate pass listed every `store.act` call with no `PendingAction` within 14 lines and checked the spending or irreversible ones: most are purchase screens that show the cost next to the button (the button is the confirmation); Luxury purchase, property renovation and selling a building to a tenant were missing a confirmation and now have one.

Verdict key: OK = every toast depends on an engine result or is an honest information message; Fixed = changed in this pass; Open = not changed.

| File | show calls | Verdict |
|---|---|---|
| Features/Companies/GroupOffice.swift | 30 | Fixed: Review all (result count / empty), right hand (3 buttons) report the engine result. |
| Features/Phone/VenturesView.swift | 29 | Fixed: walk away, decline, builders, coders, model, internal percent now report the engine SettingResult. |
| Features/Phone/MoneyPeopleActions.swift | 24 | Fixed: Meet fund managers reports the candidates found or none. Rest result-dependent. |
| Features/Companies/CompanyMarket.swift | 18 | Checked: toasts depend on engine results. Price change toast uses the real change returned. |
| Features/Companies/CompanySettings.swift | 17 | OK (result-dependent; spot-checked) |
| Features/Phone/LuxuryView.swift | 16 | Fixed: Purchase now asks for confirmation (cost, upkeep, selling fee). |
| Features/Companies/CompanyManagement.swift | 15 | Fixed: authority level and the three limits report the result. Hire/dismiss already result-dependent. |
| Features/Companies/CompanyEquipment.swift | 14 | OK (result-dependent; spot-checked) |
| Features/Companies/ChainView.swift | 13 | Fixed: chain rules (price, ordering, pay, marketing) and release-knob report the engine result; slider shows Saved on release. |
| Features/Companies/CompanyClub.swift | 13 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyHolding.swift | 13 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyMoney.swift | 13 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyFranchise.swift | 12 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyProperties.swift | 12 | Fixed: Renovate and Sell to tenant now confirm. Other toasts depend on engine results. |
| Features/Companies/CompanySourcing.swift | 12 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyStaffRoster.swift | 12 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyPeopleActions.swift | 11 | OK (result-dependent; spot-checked) |
| Features/Phone/BankView.swift | 9 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanySaleSection.swift | 8 | Fixed: decline reports the result; "off the market" checks the listing is gone. |
| Features/Companies/FranchiseBrandsView.swift | 8 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyOtherSections.swift | 8 | OK (result-dependent; spot-checked) |
| Features/Companies/GivingView.swift | 8 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyProjects.swift | 8 | Fixed: Take the bid back reports a refusal when bidding has closed. |
| Features/Companies/CompanyCoverage.swift | 8 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyPayrollRun.swift | 7 | Open: "Payroll is now run by" toast after setPayrollMode (engine guard is only company existence; payroll files are being edited elsewhere). |
| Features/Companies/CompanyEnergy.swift | 7 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyOwnership.swift | 7 | Fixed: dividend policy, counter and decline report the result. |
| Features/Phone/WorldView.swift | 6 | OK (result-dependent; spot-checked) |
| Features/Phone/InvestView.swift | 6 | OK (result-dependent; spot-checked) |
| Features/Phone/ExpandAbroadView.swift | 6 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyLoans.swift | 6 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyFinanceBook.swift | 6 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyHowYouSell.swift | 6 | OK (result-dependent; spot-checked) |
| Features/Phone/NewCompanyStart.swift | 5 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyWorkplace.swift | 5 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyOverview.swift | 5 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyPayroll.swift | 5 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyChain.swift | 5 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyContracts.swift | 5 | Fixed: Take the bid back reports a refusal when bidding has closed. |
| Features/Companies/ContractDiscussionView.swift | 5 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyCustomers.swift | 5 | Fixed: cyber level and backups report the result. |
| Features/Companies/ExecutivePosts.swift | 4 | Fixed: group limit reports the result. |
| Features/Companies/CompanyTeamRoster.swift | 4 | Fixed: team authority level and limit report the result. |
| Features/Companies/CandidateSheet.swift | 3 | OK (result-dependent; spot-checked) |
| Features/Companies/ChainSuppliers.swift | 3 | Fixed: release-supplier reports the result. |
| Features/Home/GoalsCard.swift | 3 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyWaysToSell.swift | 2 | OK (result-dependent; spot-checked) |
| Features/Inbox/InboxView.swift | 2 | OK (result-dependent; spot-checked) |
| Features/Phone/SettingsView.swift | 1 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyMarketing.swift | 1 | OK (result-dependent; spot-checked) |
| Features/Companies/CompanyTeam.swift | 1 | OK (result-dependent; spot-checked) |
| Features/Companies/GroupBoards.swift | 1 | Fixed: board mode and frequency report the result. |

## Not covered

- Toasts chosen by ternary were not each opened; they were judged by pattern (`ok ? ... : ...`).
- Payroll mode, store-chain rules (`setStoreRule`), `setExecutiveAuthority`, `setOwnerSalary`, `setPriceLevel`/`setOwnerHours` and similar sliders still apply without an engine result; they show no success toast that could be wrong, but also no "Saved". Next step: give them `SettingResult` the same way.
- Money format and the scroll-under-Back fix are verified by parse only; CI screenshots must confirm both.
