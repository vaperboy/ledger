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
A `.sheet` that can raise popups must put `.popupHost()` on its content: a nested host draws its own popups and those of the root host
over the sheet. Audit: `grep -rn "\.sheet(\|fullScreenCover(" native/App`. A full screen is a pushed page, not a sheet.

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

Declared variants (`PopupVariant`), the only exceptions:
- `expensive`: gold foil footer with the amount in the label.
- `destructive`: red footer and red risk line.
- `report`: larger figure (28).
- `reward`: larger gold figure (30).
- `alert`: white text on the red alert.

`overline` is the existing `.capsLabel()` (a small caps section label inside a card).

On the roles: confirm, notice, decision, alert, error, daily report, week/month/year report, reward, ambition and unlock cards (all in
`GamePopup`, one card), and the text of every struct named `*Sheet`, `*Popup`, `*Picker` or `*Form` in Features (migrated by script,
`.font(...).foregroundStyle(Theme.ivory...)` pairs only). Remaining: popup bodies built by inline functions inside page files
(`popupContent`, `debtInfo`, `offerSheet`, `partialSheet`...), counting figures with their own gain/loss colour (they use
`PopupVariant.figureFont` / `valueFont`), and fonts that are not an ivory/gold/loss pair. New popup content must use the roles.

## Drawn once
A sheet's nested host claims the root host while it is open: the root layer hides, the nested layer draws the root's popups too, so a
notice raised by the store is shown once, over the sheet.

## Environment
Popup content is drawn at the app root, so the registering view's custom environment (palette, `insideCard`, marker budget and page
flag, `tabBarClearance`, `openHire`, `hidesRootBack`) is carried over (`PopupCarriedEnvironment`). A new custom key read in popup
content must be added there.
