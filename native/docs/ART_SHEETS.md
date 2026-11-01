# Art sheets supplied by the owner (27 Oct 2026)

Stored in `native/App/Ledger/Resources/art/`. All are AI-generated grids; every cell has a dark or light frame and some have captions beneath. The agent that slices them must find cell rectangles by pixel analysis (grid lines, frames) and write a manifest JSON next to the sheet; do not trust the row/column numbers printed on the sheets (they skip and repeat numbers).

| File | Size | Layout | Use |
|---|---|---|---|
| `premises-sheet.jpg` | 1696 x 2528 | title, then 4 columns (Small, Medium, Large, Very large) x 11 rows with a row label column: Home or Home Office, Office, Shop, Kitchen/Restaurant/Cafe, Workshop/Factory, Warehouse/Depot, Hotel, Clinic, Yard/Site, Gym/Studio, Slope/Outdoor Venue | premises pictures by kind and size band (kinds: home, office, shop, kitchen, industrial, warehouse, hotel, clinic, yard, gym, slope) |
| `luxury-sheet.jpg` | 1792 x 2400 | 6 columns x 5 groups, captions under each: Watches (6), Jewellery (6), Art and collectibles (6), Yachts (3) and private jets (3), Homes and estates (6; the first cell is a light business jet, then villa, townhouse, chalet, country estate, island) | luxury items other than cars; the sheet names differ from the game's item names, so map by category and order and reuse the same picture where the sheet has fewer pictures than the game has items |
| `cars-sheet.jpg` | 1206 x 1523 | rows = brands (logo in the left column), 3 cars per row, captions under each (cropped: 8 brands visible) | the 15 cars (c1 to c15), mapped by order within brand-like groups |
| `logos-sheet.jpg` | 1696 x 2528 | a grid of about 14 columns x 25 rows of generic brand logos on soft tinted squares (printed column numbers skip: 1,2,3,4,5,7,8,10,12,14,17,18,19,20) | logos for rival companies, rival groups and other named people/firms; pick deterministically from the rival's id, never reuse a logo for two live rivals |
| `workers-sheet.jpg` | 1696 x 2528 | portraits, casual work clothes: row 1 has 10 cells, rows 2 to 10 have 8 cells each (about 82 faces) | extra casual faces for workers and any non-suit staff |
| `managers-sheet.jpg` | 1696 x 2528 | 10 x 10 portraits in business wear | extra suit faces for managers, assistants, advisers, lawyers, accountants and workers in suit businesses |
| `trophies-sheet.jpg` | 2048 x 2048 | 6 x 6 trophies, badges and milestones with captions: Golden Globe, Rising Star, Glass Obelisk, Winged Triumph, Ornate Keys, Ceremonial Gavel / First Million, Exchange Bell, Key to the City, Ten Year Shield, Top Ten Plaque, Global Scale / Aviation-Builders, Industrial Gear, Maritime Anchor, Culinary Prize, Tech Achievement, Health and Care / Five-Star Plaque, Standard Approval, Safety Shield, Official Certificate, Green Ecology, Excellence Medal / Asset Reserve, Market Bull, Heritage Cup, Crystal Diamond, Crest of Honor, Value Token / Honor Ribbon, Exemplar Silver, Civic Merit, Unique Crest, Victors Medal, Civic Collar | achievements, business awards and milestones (Phone > Goals / Achievements / Rich list awards) |

Rules: pictures never carry text the game contradicts; where a sheet cell has a caption or printed label, crop it away. Keep the icon-circle fallback when a picture is missing.

## Sliced cells and how the game uses them (28 Oct 2026)

`native/tools/slice_sheets.py` (Python, PIL, numpy) finds the picture rectangles by pixel analysis (rows and columns of pixels that differ from the page colour; captions and labels fall outside), crops them and writes `Resources/art/cells/<sheet>/<cell>.jpg` plus `cells/<sheet>/manifest.json` (`cells` maps cell id to `file`, `row`, `col`, `caption`). Re-run with `python3 native/tools/slice_sheets.py [premises|luxury|cars|logos|trophies]`. The face sheets are not sliced here. `project.yml` bundles `cells/` as a folder reference; `Design/ArtLibrary.swift` reads the manifests and holds all mappings; `ThumbnailView` shows them (kinds `premisesPhoto` 16:9, `luxury`, `logo`, `trophy`) and keeps its icon fallback when a picture is missing. A picture in the asset catalogue (`thumb-luxury-<id>`) still wins over a sheet cell.

| Sheet | Cell ids | Output |
|---|---|---|
| premises | `<kind>-<band>` (kind: home, office, shop, kitchen, industrial, warehouse, hotel, clinic, yard, gym, slope; band: small, medium, large, xlarge) | 640 x 360 |
| luxury | `<group>-<n>` (watches, jewellery, art, yachtjet, homes; n = 1..6 left to right) | 512 x 384 |
| cars | `b<brand row>-<column>` (8 brands x 3; the last brand row is cropped on the sheet) | 512 x 250 (not cut to 4:3, the cars are very wide) |
| logos | `l001` to `l308` (22 rows x 14 columns, reading order) | 192 x 192 |
| trophies | `t01` to `t36` (reading order) | 384 x 384 |

### Premises band by floor area
Under 50 m2 small, 50 to under 150 medium, 150 to under 500 large, 500 and more xlarge (`ArtLibrary.premisesBand`). Kind is the trade's engine `premisesKind`; a kind without a row (none) shows the icon.

### Luxury items (game id -> cell)
Cars (cars sheet): c15 b2-2, c1 b2-1, c11 b1-3, c10 b1-2, c7 b1-1, c8 b6-3, c9 b6-2, c2 b5-1, c4 b3-1, c3 b3-2, c14 b7-3, c13 b3-3 (SUV), c12 b4-1 (limousine), c5 b7-1, c6 b5-2.
Luxury sheet: w2 watches-1, w1 watches-2, w5 watches-3, w3 jewellery-1 (necklace), w4 watches-4, w6 watches-5, w7 watches-6, w8 watches-3 (reused); a1 art-1, a2 art-4, a3 art-5, a4 art-2, a5 art-1 (reused); y1 yachtjet-3, y2 yachtjet-2, y3 yachtjet-1; j1 homes-1 (light jet), j2 yachtjet-6, j4 yachtjet-5, j3 yachtjet-4, j5 yachtjet-4 (reused); h3 homes-4, h4 homes-2, h1 homes-2, h2 homes-2 (reused); e4 homes-4, e3 homes-5, e1 homes-5, e5 homes-5, e2 homes-6. Several sheet pictures (rings, earrings, vases) have no game item and stay unused, while houses and estates reuse the few that fit.

### Logos
`ArtLibrary.logoKey(for:)`: an FNV-1a hash of the firm key picks the start, a taken logo moves on to the next free one, and when all 308 are taken the firm gets none and the slot shows initials. Assignments are remembered in UserDefaults (`art.logo.assignments`). Keys: `group|<group id>` (rival groups, group profile, Top 50), `rival|co<company id>|<rival id>` (named rivals in Market and the rival sheet, Top 50 rows), `firm|<id>` (other Top 50 firms). The Rich list shows people, not firms, so it has no logos.

### Trophies and awards (engine id -> cell)
Exact: cust t02, emp t31, profit t30, year t24, mgr t05, branch t13, div t25, abroad t12, ten t31, hundred t31, million t07 (First Million), tenm t25, hm t26, bn t28, bank t25, fam t12, hold t29, oil t14, club t35, listed t08 (Exchange Bell), su1 t02, sux t08, pe1 t25, pe2 t30, boty t03, acq t06 (Gavel), give and g10 t09 (Key to the City), stars and st48 t19, tyall t01, rd t17, ten10 and mgr10 t10 (Ten Year Shield), hq5 t24, abr50 t12, lx1 t28, lxj t13, lxy t15, lxe t09, lxi t01, lxm t03, lxw t30, lxc5 t27, no1 t01, top10 t11 (Top Ten Plaque), team56 t29, yr5 t27, yr10 t10, yr25 and yr50 t34, rk50 t32, rk3 t11, rk1 t01, nw5b, nw10b and nw50b t28.
Ladder prefixes: nw t25, dv t30, tx t33, pf t26, jb t31, mg t05, co t13, ty t14, cc t12, aw t04, n1 t01, ch t14, fr t22. Anything else uses its group: first t02, money t25, people t31, trades t14, world t12, legacy t29, market t11; last resort t24 (Excellence Medal).
Business awards (Rich list): boty t03, emp t31, rated t19, new t02, grow t04, ent t01.
