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

## Left for the owner

| File:line | What | Question |
|---|---|---|
| Home/HomeView.swift:338,380 | "Inbox · N" link and "N decisions waiting" card open the Inbox | Keep as a badge-style entry, or drop for a number only? |
| Home/HomeView.swift:327, HomeRankStrip, HomeShortcut | Goals card, rank strip, shortcuts open apps, hiring, market | Is Home allowed to launch apps, or numbers only? |
| Home/HomeView.swift:231 | `openHiring()` falls back to Group > Management | Hiring entry point must be Team only |
| Phone/BankAccountView.swift:74, BankBillsTab.swift:52 | Payroll alerts with "Run payroll" / "Open Accounting" | These are needs-you items: answer in the Inbox, or stay as Bank alerts? |
| Companies/CompanyManagement.swift:403 | "Talk in the Boardroom" (inside Group, to another Group tab) | Same feature, or a duplicate home? |
| Companies/GroupHome.swift:383 | Group row without a manager opens Team (staff) | The Group row should be the manager; what should an unmanaged row do? |
| Companies/GroupEntityPage.swift:145,155,215; GroupBoards.swift:101 | Group pages link to Company Team and sections | Group-to-Company links, same question |
| Companies/CompanySetupScreen.swift:68,70; CompanyOperations.swift:124-132; CompanyOperationsSheets.swift:39; CompanyEquipment.swift:189-408 | Company rows open AirStay, TechPro, Atlas (rent, buy, cover) | These are the purchase actions; need a home inside Company or remain in the apps |
| Companies/DocumentSignSheet.swift:123, GroupSupplierDirectory.swift:200, ProjectsTabs.swift:82,319,376, ProjectTimelineViews.swift:53 | Redirects to company sections | Decide per screen |
| Market/* (MarketCompanies:258, MarketWorld:145, MarketRivals:313-453), WorldRecordsView:163 | Open Company after acquisitions and from lists | Post-purchase navigation allowed? |
| Phone/BankApp.swift:89, NewsView.swift:173, VenturesView.swift:248, StatsView.swift:241 | Phone apps open Company or other apps | Same |
| Reports/WeekReportShell.swift:93,113, ReportPrompt.swift:162 | "Next goal" link and "Full report" open other places | Same |
| Home dashboard duplicates | HomeInsights and Suggestions repeat per-feature facts | Needs a content review, not a code-only fix |

Not compiled here; CI is the compiler.
