# Home mockups A / B / C (brief Part 10)

The PNGs in `png/` are HTML replicas, not SwiftUI renders: `ImageRenderer` cannot run on this machine (Linux, no Xcode).
They are drawn by `html/build.js` (Playwright Chromium, 390x844 at 2x, dark mode) with the same colours, radii and sizes as `Design/Theme.swift`.
Fonts differ slightly (Inter for the system sans, Liberation Serif for the serif) and app icons are generic outline glyphs.

- `MockupA_Current.swift`, `MockupB_Feed.swift`, `MockupC_Split.swift`: static SwiftUI, three `#Preview` each (Home, DayClose, WeekReport).
- `MockupKit.swift`: shared pieces (cards, tab bar, day bar, day close, report parts). Uses `Theme` only.
- Excluded from the Ledger target in `project.yml`; not compiled by CI. Not compiled anywhere yet: checked by inspection only.
- Notes: A adds one text line (company and cash) under the date, since today's Home shows no cash. C's dashboard also shows the 7-segment bar.

Rebuild the PNGs: `cd html && NODE_PATH=<global node_modules> node build.js`.
