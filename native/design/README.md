# Design directions

`mockups/` holds the five directions drawn from real game data (Dashboard, Group, Company management), and `src/` the
Python that generates them (`python3 gen.py`, then `node render.js <file>.html`; fonts are not included, they are Google Fonts).

| # | Name | Status |
|---|------|--------|
| 1 | Ivory Ledger | **Shipped.** Spec in `STYLE_IVORY_LEDGER.md` |
| 2 | Command Grid | Kept for later (purchasable style) |
| 3 | Walnut Study | Kept for later |
| 4 | Glass Native | Kept for later |
| 5 | Skyline Luxe | Kept for later |

Styles live behind the tokens in `App/Ledger/Design/Theme.swift`, so another style is a second set of tokens plus a few components.
