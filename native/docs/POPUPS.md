# Popups

One popup system. Every popup of the app is drawn by ONE host at the app root, as an overlay above the whole app (tab bar included).
No `fullScreenCover`, `.sheet`, `confirmationDialog` or `alert` for popups, so a popup never changes navigation state.

## How it works
- `PopupHost` (Design/PopupHost.swift) holds the registered popups; `PopupHostLayer` draws them. `RootView` owns the root host and puts it
  in the environment (`\.popupHost`).
- A popup REGISTERS its card content (kept as `AnyView`) while it is wanted: the call-site API is unchanged.
  `.centerSheet(isPresented:/item:)`, `.confirmAction($pending)`, and `PopupLayer` (notice, decision, red alert, report, daily, ambition,
  reward, unlock, error) all register. Closing sets the original binding to `false` / `nil`.
- Every registered popup stays in the hierarchy (its state survives while another is on top); only the first in queue order is visible
  and takes touches. Others wait, hidden.
- The card is `CenterSheetFrame` (`.card` entries: header with title left and x right, tap outside closes unless `.centerSheetLocked()`)
  or a popup that draws its own (`GamePopup`, report page: `.raw`). Spring in/out; none under Reduce Motion.
- A view inside a popup closes it with `popupClose` (the views that used `\.dismiss` call it first; the system dismiss would pop the page).
- The palette of the view that registered a popup is carried over (an outside app keeps its colours).

## Queue order (`PopupPriority`, pure logic in `PopupQueue`, tested in `PopupQueueTests`)
1. `confirm` (Are you sure, errors, banner question), a stack: newest on top
2. `decision`
3. `alert` (red alert)
4. `notice`
5. `report` (week, month, year, daily, ambition choice)
6. `celebration` (rewards)
7. `panel` (everything the player opened: worker profile, pickers, forms), a stack: newest on top

Inside a level other than confirm and panel: oldest first, one after another. A confirm raised from a panel shows above it; the panel
returns when it is answered.

## Sheets
A `.sheet` that can raise popups must put `.popupHost()` on its content: a nested host draws its own popups and those of every host above
it over the sheet. A full screen is a pushed page, not a sheet. The one sheet left is the loan application flow (see the audit).

## Audit of system presentations
`grep -rnE "\.sheet\(|fullScreenCover\(|\.alert\(|confirmationDialog\(|\.popover\(|actionSheet|UIAlertController" native/App/Ledger`
Decision: POPUP = converted to `.centerSheet` / `.confirmAction` / `GamePopup` through the host; FULL SCREEN = kept, with `.popupHost()`
inside when it can raise popups; SYSTEM = a system picker or menu, kept.

| Site | What it is | Decision |
|---|---|---|
| `BankView.swift` BankLoansTab `.sheet` | `BankLoanApplyFlow`: three steps with its own header, step dots and swipe-back | FULL SCREEN (kept, `.popupHost()` inside) |
| `CarDealerSection.swift` `.sheet(item:)` | `CarPriceSheet`: one car, price slider | POPUP (`centerSheet(item:)`, fit) |
| `CarDealerSection.swift` `.sheet(isPresented: $ordering)` | `CarOrderSheet`: list of cars to order | POPUP (`centerSheet`, fit) |
| `CarDealerSection.swift` `.sheet(isPresented: $brandScreen)` | `CarBrandScreen`: brand list that opens terms pages | POPUP (`centerSheet`, `.tall`, `PopupStack`, step back) |
| `PopupKit.swift` `.popover` (`contextPopover`, `InfoPopoverButton`) | a short note anchored to its (i) button | SYSTEM (contextual popover, kept on purpose) |
| `SettingsView.swift` `.fileImporter` | importing a save file | SYSTEM picker (kept) |
| `SettingsView.swift` `ShareLink` | exporting a save | SYSTEM share sheet (kept) |
| `Menu`, `Picker(.menu)`, `.contextMenu` (about 70 sites) | pick one of a few options | SYSTEM menus (kept) |
| `.fullScreenCover`, `.alert`, `.confirmationDialog`, `.actionSheet`, `UIAlertController` | none left | none |

Counts: 4 `.sheet` (1 full screen kept, 3 converted to popups), 0 `fullScreenCover`, 0 alerts and dialogs, 1 popover kept, 1 file importer
and 1 share link kept, about 70 system menus kept. Everything else the player sees as a popup already goes through the host.

## Tall popups with their own pages: step back
`PopupStack` (Design/PopupStack.swift) is the content of a `.tall` popup that holds pages (a list that opens a detail page). Pages are
pushed with `NavigationLink(value:)`; the stack supplies `.navigationDestination(for:)`. Inside it `popupClose`, and so the `dismiss()`
helper every popup view has, is a STEP BACK: it pops one page, and closes the popup only at the root (`PopupStep.forClose`, tested). The x
of the card and a tap outside still close the whole popup. The root hides the system navigation bar (the card has its header); a
pushed page shows it with the system back button and its `navigationTitle`. Used by `CarBrandScreen`.

## Adding a popup
- Opened by the player: `.centerSheet(isPresented: $flag, title: "...") { content }` (or `item:`). Content never draws its own close.
- A question: set a `PendingAction` through `.confirmAction($pending)`.
- A game message: `store.tell/show`; a new kind: `.hostedPopup(key:priority:active:onClose:) { ... }` in `PopupLayer`.

## Text and form rules (Design/PopupStyle.swift)
Content names a ROLE; it never sets a font, size or colour.
| Role | Use | Look |
|---|---|---|
| title | header | serif 16 semibold |
| subtitle | line under a heading | 12.5 soft |
| body | running text | 14 ink |
| caption | note, option detail | 12 soft |
| figure | key amount | serif 22, monospaced digits |
| rowLabel / rowValue | `PopupRow`, label left, value right | 13 soft / 13.5 medium |
| effect | what an option does | 12 gold |
| risk | risk, validation (`InlineMessage`) | 12.5 caution |
| button | footer label | 14 medium |

One card (rounded hero radius, max 560 wide, max 80% high, 22 margin), one header (44pt, title left, x right), one spacing scale
(`PopupSpace`: 4, 8, 12, 16), one footer (`PopupFooter`, Cancel | Apply).

`code` is the extra role for text the player does not read as prose (a pasted save): 12 monospaced. A text field in a popup is
`TextField(...).popupField()` (15, ink, 44pt, deep fill and hairline; Design/PopupStyle.swift).

Declared variants (`PopupVariant`), the only exceptions:
- `expensive`: gold foil footer with the amount in the label.
- `destructive`: red footer and red risk line.
- `report`: larger figure (28).
- `reward`: larger gold figure (30).
- `alert`: white text on the red alert.

`overline` is the existing `.capsLabel()` (a small caps section label inside a card).

On the roles: confirm, notice, decision, alert, error, daily report, week/month/year report, reward, ambition and unlock cards (all in
`GamePopup`, one card), the text of every struct named `*Sheet`, `*Popup`, `*Picker` or `*Form` in Features, and the inline popup bodies
in page files (supplier popup, supplier directory profile, debt note, club offer, starter trade, rename chain, property card and tenants,
paste save text, Inbox decision, hire page, contract discussion, shortcut editor, group add menu, car sheets). Two gain/loss tones that
no declared role has map to the nearest role (a good result is `effect`, a bad or warning one `risk`; a negotiation answer is
`HireFeedback.popupRole`).
Kept as they are, on purpose: counting figures with their own gain/loss colour (they use `PopupVariant.figureFont` / `valueFont`); the
message bubble of `MessageCard` (the same view is a row of the Inbox list); `DocumentView` (a paper document); the marketplace deal
hero price (42, bespoke); luxury settlement rows and tiles; tile labels and picture grids (`CustomTabPicker`); `Menu` and `Picker`
labels; icons. New popup content must use the roles.

## Drawn once
A sheet's nested host claims the host above it while it is open (`PopupHost.attach(to:)`): the layer above hides (`drawnEntries()` is
empty), the nested layer draws the popups of every host above it too (`gathered()`), so a notice raised by the store is shown once,
over the sheet, in the one queue. The claim is taken once and given back once (`detach`, on disappear), and also when the nested host
is deallocated, so a sheet that vanishes without `onDisappear` cannot leave the root silent for good. A sheet inside a sheet still
draws everything once, in the innermost layer. Tested in `PopupHostTests`.

## Environment
Popup content is drawn at the app root, so the registering view's custom environment (palette, `insideCard`, marker budget and page
flag, `tabBarClearance`, `openHire`, `hidesRootBack`) is carried over (`PopupCarriedEnvironment`). A new custom key read in popup
content must be added there.

## Traces: popups never touch navigation (read from the code)
Nothing in the popup path writes navigation state:
- A popup is registered by a zero-size `PopupRegistration` (a hidden UIView in the registering view's background) and drawn by the
  host's layer at the app root as an overlay. It is not a presentation, so no `onAppear` / `onDisappear` of any page runs when it opens
  or closes. The only `onDisappear` in the app is the nested host's (`.popupHost()`).
- Every `dismiss()` in popup content is a private helper `popupClose ?? systemDismiss`. Inside a popup `popupClose` is always set, so
  the system `\.dismiss` (which would pop the page under the popup) is never reached from popup content. In a page `popupClose` is nil.
  `grep -rn "Environment(.dismiss)" native/App/Ledger` finds only the `systemDismiss` fallbacks.
- `store.act` replaces `engine` and re-renders the pages, but no page branch changes (the `if let e = store.engine, let co = ...` guards
  stay true), so view identity and `@State` (`part`, `popup`, `pending`) are kept. Nothing in a popup writes `part`, `showSupplying`,
  `detailID` of another page or a route path.
- `navigationDestination(isPresented:)` bindings with computed setters (`CompanyOperations`, `CompanySales`, `CompanyMoney`,
  `InvestView`: `part != .setup`, set false resets `part`) are written only by the system on a real pop and by the table rows that open
  a page. They are deliberately NOT made tolerant of a `false` while a popup is up: ignoring it cannot bring a popped page back and
  would leave `part` stuck, so the page would re-open by itself the next time the company is shown.

| Flow | Path | Verdict |
|---|---|---|
| Company > Manage > Operations > Suppliers > tap a supplier | `optionRow` sets `popup`; `centerSheet(item:)` registers `supplierPopup`; Use / lunch call `closeThen` (sets `popup = nil`, asks 0.45 s later through `confirmAction`) | no navigation write; `part`, `showSupplying` untouched |
| Hire discussion (worker profile, `ContractDiscussionView`, `HireFlowSheet`/`HireOnePage`) | a popup raised in a popup: both `.panel`, newest on top, the profile stays registered and returns; `HireOnePage.model.finished` calls its `dismiss()` helper = `popupClose`; `openHire` is carried into the popup | closes only the popup |
| Loan apply | the one kept `.sheet`; `.popupHost()` makes its confirmations draw once over the sheet; `dismiss()` there is the system one (no `popupClose` above it) and closes the sheet | no stack change |
| Marketplace buy | `MarketplaceDealView` in `centerSheet`; `onBought` sets `talking = false` and `openID = nil` (the app's own state, not a pushed page) | in-app step only |
| Item price (`SalesItemSheet`, `ItemPageView`) | the slider commits through `store.act`; a refusal is a notice popup (priority `notice`, above the panel) | no navigation |
| Inbox decision | `MessageCard.ask` sets `pending`; the confirmation (priority `confirm`) is registered once (the list binding is nil while the detail popup is open); the answer runs on the next run loop after the card is gone | no navigation; the popup closes itself (`detailID = nil`) |
