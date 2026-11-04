# Centred popup sites (`.centerSheet`)

Frame: `Design/CenterSheet.swift`. The frame draws a fixed 44pt header row (optional title left, x right, thin divider under it only with a title). Content starts below it and never draws its own close button. A title is set with `title:` on `centerSheet(...)` or, when it depends on the content, with `.centerSheetTitle("...")` inside the content (PeopleSheet does this).

Size: `size: .fit` (default) is exactly as high as the content, at most 80% of the screen, scrolling only when taller (FitScroll, content padding 16 added by the frame). `size: .tall` is a fixed 80% and is used only for flows and full-bleed content. No heuristics: `PopupNavStack`, `centerSheetFills` and the greedy measurement are gone. A content must not contain its own ScrollView/NavigationStack when `.fit`.

Shared metrics (`PopupMetrics`, `PopupHeaderRow` in CenterSheet.swift) are used by both `CenterSheetFrame` and `GamePopup`: max width 560, side margin 22, corner radius `Theme.Radius.hero`, 44pt header row (title serif 16, up to two lines, x 44pt target), room 80% of the screen. `GamePopup` (confirm, notice, daily report, decision, rename, banner question) used to be a different card (max 420, 20pt title, 36pt x, no height limit, so long content clipped on iPhone SE); it now hugs its content in a FitScroll under the same header. Confirm/notice cards have no x (only their buttons answer). `size: .fitBleed` is `.fit` without the 16pt content padding, for full-bleed photos. Only two sites stay `.tall`: the hire flow (HireFlowSheet, a NavigationStack with two long form pages, so its height cannot be measured; the pages are longer than 80% on most phones) and Settings from Start (a long page with its own ScrollView, shared with the Phone Settings app, so its ScrollView and background are kept). Content of a `.fit` popup must not contain Spacer(maxHeight infinity), GeometryReader without a fixed height, ScrollView, NavigationStack or its own background.

Root causes fixed: (1) the x was an overlay on top of the content, so it covered titles and buttons, and content added its own x; (2) a NavigationStack (PopupNavStack, PeopleSheet) inside the unbounded FitScroll collapses to zero height, so the card was either blank or forced to 80% with empty space; (3) `.ledgerBackground()` painted a second panel inside the card.

| File | Shows | Size | Own close before | Fixed |
|---|---|---|---|---|
| Phone/BankAccountView.swift | Bank move (deposit/withdraw/transfer) | fit | toolbar Close | stack removed, heading in content |
| Phone/BankAccountView.swift | Pay bill | fit | toolbar Done | stack removed, title "Pay bill" |
| Phone/BankAccountView.swift | Every movement | fit | toolbar Done | stack removed, title |
| Phone/BankAccountsView.swift | Bank move (personal) | fit | via BankMoveSheet | as above |
| Phone/VenturesView.swift | Found a startup | fit (scroll removed, hugs, max 80%) | header Close | header removed, title |
| Phone/VenturesView.swift | Launch / change price | fit (scroll removed) | header Close | header removed, title |
| Phone/StatsView.swift | Document | fit | x in DocumentView | x removed from DocumentView |
| Phone/BankView.swift | Loan details | fit | toolbar Close | stack removed, title |
| Phone/BankLoanDetail.swift | Part payment | fit | toolbar Close | stack removed, title "Pay back" |
| Phone/LuxuryView.swift | Item purchase | fitBleed (scroll removed, footer at the end, full-bleed photo) | Close capsule | removed from LuxuryItemHead |
| Phone/LuxuryView.swift | Inspect piece | fitBleed (scroll removed) | Close capsule | removed |
| Companies/CompanySales.swift (3 sites) | Marketing, sales item (price slider), new item | fit | none (item used PeopleSheet Done) | no stack/background |
| Companies/GroupEntityMoney.swift | Bank move (company), dividend policy | fit | Close button | removed |
| Companies/CompanySaleSection.swift | Buyer talk | fit | toolbar Close | stack removed |
| Companies/GroupEntityBoard.swift | Board seat picker | fit | Close button | removed |
| Companies/FranchiseBrandsView.swift, CompanyFranchise.swift, CompanyChain.swift, CompanySetupScreen.swift, DocumentSignSheet.swift | Sign and send forms | fit, locked | GamePopup inside popup (second card and x) | plain content, title and lock via frame |
| Companies/CompanyDevelopment.swift | Expansion plan | fit | bottom Close | removed |
| Companies/CompanyClub.swift | Club offer | fit | Close button | removed |
| Companies/CompanyTeam.swift | Perks | fit | none | title in header |
| Companies/GroupSupplierDirectory.swift, CompanySourcing.swift (2) | Supplier profile, supplier popup, credit info | fit | none | inner ContainedScroll removed, own padding removed |
| Companies/CompanySettings.swift | Limited company conversion | fit (scroll removed) | toolbar Cancel/Close | stack removed, title |
| Companies/CompanyTeamRoster.swift, CompanyManagement.swift (2), CompanyProperties.swift, CompanyOperations.swift | Post, manager, assistant, property, setting | fit | PeopleSheet Done | PeopleSheet no longer a stack |
| Companies/CompanyLoans.swift | Loan details, repay | fit | toolbar Close | stack removed |
| Companies/GrowthBrandResearch.swift | Market research (+ report with Back) | fit | x in DocumentView | ContainedScroll removed, report switches by @State |
| Companies/CompanyMarket.swift | Rival; Acquisition | fit; fit (acquisition, scroll removed) | toolbar Done/Not now | stacks removed |
| Companies/WorkerProfileSheet.swift (RootView, CompanyStaffRoster) | Worker profile | fit | none | stack removed |
| Companies/HireFlowKit.swift | Hire flow | tall (NavigationStack) | none | `NavigationStack`, `size: .tall` |
| Companies/DecidesSheets.swift | Decision rows, manager | fit | none | background removed |
| Companies/GroupView.swift | Add to group menu | fit | none | title in header |
| Companies/CompanyStaffRoster.swift | Contract discussion | fit | PeopleSheet Done | as PeopleSheet |
| Home/HomeView.swift (HomeShortcutEditor) | Home shortcuts | fit | Done at top | Save button at bottom, scroll removed |
| Inbox/InboxView.swift | Message / document | fit | two x buttons | x removed, no nested bubble card |
| Start/StartView.swift | Paste save text | fit | toolbar Cancel | stack removed |
| Root/RootView.swift | Worker profile, custom tab picker | fit | none | title in header |
| Start/NewPlayerSetup.swift | Starter trade (cost, start cash, open) | fit | native `.sheet` with `.presentationDetents([.height(300)])` | now `.centerSheet`, title via `.centerSheetTitle`, own padding/background removed |
| Start/StartView.swift | Settings (page with own ScrollView) | tall (exception, long page) | native full `.sheet` + AppHeader Close | now `.centerSheet(size: .tall)`, title "Settings"; header removed |
| Phone/SettingsView.swift, Phone/MarketplaceListing.swift | Paste save, Message seller | fit | none | unchanged |
| Companies/EntityRequirements.swift, Root/GamePopups.swift (UnlockPopup), Home/HomeView.swift | Paper, feature unlock, shortcuts | fit | none | unchanged |
| GamePopup users: ConfirmPopup, Notice/Acquired/Done/Decision/Red alert, MorningBriefing, NotificationBanner, ChainView rename, RootView error | Questions, notices, daily report | fit (GamePopup) | own 420 card, 36pt x | shared metrics + FitScroll; DecisionPopup's own FitScroll(460) removed |

Remaining native covers: `ConfirmActionModifier` and the ChainView rename use `.fullScreenCover` with a clear background to draw a GamePopup; that is the same centred card, not a native sheet. `.contextPopover` (InfoPopoverButton) stays a small anchored popover. No `.confirmationDialog` in the app.
