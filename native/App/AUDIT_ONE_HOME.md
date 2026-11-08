# Audit: one home per feature, zero redirects

Rules: managers live in Group (the Group row is the manager); employees live in the company's Team; each screen shows only its own feature; needs-you items are answered in the Inbox; Home is a pure dashboard. Only badges may point across features. Paths are under `Ledger/Features/`; line numbers are from the audited base.

## Fixed (removed, no longer compiled in)

| File:line | What | Fix |
|---|---|---|
| Companies/CompanyTeam.swift:116 | Team row "Managers and executives" opened Group | Row removed |
| Companies/CompanyPayroll.swift:21 | "Run payroll in Accounting" row | Row removed |
| Companies/CompanyMoney.swift:122,124 | Ownership row (Group) and Statements row (Accounting) | Rows removed, unused vars dropped |
| Companies/CompanyCustomers.swift:94 | "What customers wrote" opened Reviews app | Link and helper removed |
| Companies/CompanyHolding.swift:80 | "Dividends to you" opened Group > Money | Row removed |
| Accounting/AccountingPayroll.swift:129,180,184,346 | Move money in the Bank; payroll-mode rows opened Atlas / Group | Buttons and links removed |
| Accounting/AccountingSettings.swift:83 | "Change accountant" opened Atlas | Button removed |
| Accounting/AccountingSuppliers.swift:70 | "Compare suppliers" opened Company Suppliers | Block removed |
| Accounting/AccountingDocuments.swift:112-122 | Financing, insurance, chain rows opened Bank, Atlas, Company | Rows are read-only |
| Accounting/AccountingTransactions.swift:250 | Loan record opened the Bank | Read-only row |
| Inbox/InboxView.swift:233,468,500 | "Open company/applicants/app" links and swipe action | Removed; `section(for:)` and `applicantLink` deleted |
| Reports/ReportLedger.swift:95,138 | Movement and upcoming rows opened Company finances | Plain rows |
| Reports/ReportsView.swift:262 | Company rows opened the company | Plain rows |
| Phone/BankBillsTab.swift:93 | "Payroll and pay day" card opened Accounting | Card removed |
| Phone/BankMoveSheets.swift:136 | "Open the company" button | Button removed |

## Resolved by owner decisions

| File:line | What | Resolution |
|---|---|---|
| Home/HomeView.swift:231 | `openHiring()` fell back to Group > Management | Opens the Team of the company with an open post, else the first live company; nothing otherwise |
| Phone/BankAccountView.swift:74, BankBillsTab.swift:52 | Payroll alerts with "Run payroll" / "Open Accounting" | Removed from Bank; the Inbox "Needs you" tab lists them with "Approve payroll" / "Pay now" answered there |
| Companies/CompanyManagement.swift:403 | "Talk in the Boardroom" | Button removed |
| Companies/GroupHome.swift:383 | Unmanaged Group row opened Team | Row is plain |
| Companies/GroupEntityPage.swift:145,155,215 | Staff, Open the company, subsidiary rows opened Company | Removed; subsidiaries are plain rows |
| Companies/CompanySetupScreen.swift:68,70; CompanyOperations.swift:124-132; CompanyOperationsSheets.swift:39; CompanyEquipment.swift | Rows opened AirStay, TechPro, Atlas | Removed; the flows live only in the apps (rows are read-only, the Not insured and Outgrown-home fix cards are gone) |
| Companies/DocumentSignSheet.swift:123, GroupSupplierDirectory.swift:200, ProjectsTabs.swift, ProjectTimelineViews.swift:53 | Redirects to company sections | Removed (project company rows are plain, the Start-something tiles keep only Venture) |
| Market/MarketCompanies:258, MarketWorld:145, MarketRivals:313-453, WorldRecordsView:163 | Open Company after acquisitions and from lists | Removed; the post-purchase toast stays |
| Companies/ProjectsTabs.swift (Venture tile) | Opened the Ventures app | The tile is a `VenturesGlance` row (value, change, offers) that opens the Portfolio part of Projects; the portfolio is `VenturesHome` (Phone/VenturesView.swift), shared with the standalone Ventures phone app, which only adds its header |
| Phone/BankApp.swift:89, NewsView.swift:173, VenturesView.swift:248, StatsView.swift:241 | Phone apps opened Company or other apps | Removed (Stats keeps the Activity page) |
| Reports/WeekReportShell.swift:93,113, ReportPrompt.swift:162 | "Next goal" link and "Full report" | Removed with `openReport` and the `openReports` parameter |

## Still open

| File:line | What | Question |
|---|---|---|
| Home/* | Home launches apps and the Inbox; HomeInsights and Suggestions repeat per-feature facts | Home was not touched in this pass |

Not compiled here; CI is the compiler.
