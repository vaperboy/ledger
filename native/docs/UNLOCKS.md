# Progressive unlocks (owner spec, 3 Nov 2026)

Essentials are never gated: Overview, Management, Money, Deals, Sales, Inbox and Bank are always open. Engine: `Businesses/Unlocks.swift`
(`engine.unlockState(companyID:)`, `pendingUnlocks()`, `markUnlockShown(id:companyID:)`). App: `Design/UnlockKit.swift` (popup, `LockedBlock`).
Nothing locks what a company already uses (an existing chain, franchise, board, report or dividend keeps its feature open).

| id | Feature | Opens when | Locked behaviour |
|---|---|---|---|
| board | Group entity > Board | a board exists (chain or co-owners), a search lined up candidates, or a limited company has a manager who could take a seat | HIDDEN (meaningless with nobody to add); a deep link falls back to Overview |
| chain | Chain registration (Expansion) | the company has traded 52 weeks | LOCKED block with a thin progress line; the requirement rows stay visible so the papers can be prepared meanwhile |
| franchise | Franchising (Expansion) | proven concept: 52 weeks and four profitable quarters | the proven-concept requirement row carries the progress; launch stays closed until every row is Done |
| abroad | Expand abroad (Expansion) | twelve closed months in profit, or a foreign subsidiary already exists | LOCKED block with a thin progress line (months on record) |
| research | Market research (Sales card, Market app) | the company is 8 weeks old, or already has a report | dimmed row with a lock and "Locked"; tapping shows the reason popup |
| dividends | Dividend desk (Group > Money) | a limited company with retained profit to pay out (or one that has paid before); holdings are never locked | LOCKED block |
| marketplace | Marketplace / used car dealing | any live company | always open; silent (never announced) |

Hidden vs locked: only Board is hidden. Every other item stays visible, dimmed, with a lock and one line "Unlocks when ...".

Announcements: the weekly sweep records a newly satisfied unlock once per company in `rest["unlk"]` (`{companyID: {id: {w, shown}}}`).
A save without `unlk` is seeded silently on its first sweep (everything already satisfied is marked shown). The app queues pending items
after the daily briefing and every other popup (`GameStore.unlockQueue`, held like the celebration queue), shows one centred locked popup
("<Feature> unlocked!", Take me there highlighted, Skip quiet) and marks it shown on either button or the close button.
