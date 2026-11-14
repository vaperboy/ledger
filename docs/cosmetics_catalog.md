# Cosmetics catalogue

Every item a player can own on the profile or avatar. Generated from `cosmetics/gold_cosmetics.json` and `season/season_N.json`; the engine reads those files, this table is a copy for reading.

Art: `file` has a picture in `Resources/Content/art`; `slot` is drawn as a placeholder until the file exists (the slot name is the item's `art` field).

## Where things drop

- **Boxes.** A cosmetic row of rarity R in a box draws one item at random from the box pool of rarity R: every `Boxes` and `Store` item below with that rarity, minus items already owned. Odds per box are in `boxes/boxes.json` (weights add to 10000) and are shown in the app; ten paid boxes without a rare or better guarantee one.
  - Season box: common 15.0%, rare 3.7%, epic 1.0%
  - Cabinet box: common 28.0%, rare 8.0%, epic 2.5%, legendary 0.4%
  - Grand box: common 15.0%, rare 13.0%, epic 4.5%, legendary 1.0%
- **Store.** Store items are also sold for gold: common 15, rare 35, epic 80. Legendary items are box-only.
- **Earned.** Level, rank and career goal outfits are given for reaching them and are bound to the account. Free items are owned from the start. Plan items come with a Ledger plan.
- **Season 2** (Spring Market) is hidden everywhere until it starts, by one check on the season start day (`SeasonCatalog.isLive`).

## Items

| Kind | Id | Name | Rarity | Where it drops | Art |
|---|---|---|---|---|---|
| Outfit | `outfit.baker` | Baker's apron | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.blazer` | Blazer | common | Free | slot |
| Outfit | `outfit.bomberjk` | Bomber jacket | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.cableknit` | Cable-knit jumper | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.charcoal` | Charcoal two-piece | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.clerk` | Clerk cardigan | common | Level 3 | slot |
| Outfit | `outfit.courier` | Courier jacket | common | Level 6 | slot |
| Outfit | `outfit.denim` | Denim jacket | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.goal.bellsleeve` | Bell-sleeve blouse | common | Career goal k21 | slot |
| Outfit | `outfit.goal.coinvest` | Coin-stitched vest | common | Career goal k5 | slot |
| Outfit | `outfit.goal.regulars` | Regulars' star jacket | common | Career goal k3 | slot |
| Outfit | `outfit.greyflannel` | Grey flannel | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.hoodie` | Hoodie | common | Free | slot |
| Outfit | `outfit.intern` | Intern shirt | common | Level 2 | slot |
| Outfit | `outfit.labcoat` | Lab coat | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.linensuit` | Linen summer suit | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.parka` | Winter parka | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.polo` | Polo | common | Free | slot |
| Outfit | `outfit.rainmac` | Rain mac | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.rank.shopkeeper` | Shopkeeper's apron | common | Rank 1 | slot |
| Outfit | `outfit.rank.trader` | Trader's waistcoat | common | Rank 2 | slot |
| Outfit | `outfit.s1.pennant` | Pennant polo | common | Season 1 pass, tier 1, free | slot |
| Outfit | `outfit.s2.sprout` | Sprout apron | common | Season 2 pass, tier 1, free (hidden until it starts) | slot |
| Outfit | `outfit.safari` | Safari vest | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.sales` | Sales jacket | common | Level 4 | slot |
| Outfit | `outfit.shirt` | Shirt | common | Free | slot |
| Outfit | `outfit.sunlinen` | Summer linen shirt | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.trackjk` | Track jacket | common | Store 15 gold, boxes | slot |
| Outfit | `outfit.whites` | Chef whites | common | Level 8 | slot |
| Outfit | `outfit.aviator` | Aviator jacket | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.bomber` | Silk bomber | rare | Level 50 | slot |
| Outfit | `outfit.camel` | Camel overcoat | rare | Level 30 | slot |
| Outfit | `outfit.camelcoat` | Camel office coat | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.captain` | Captain's coat | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.flannel` | Flannel shirt | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.goal.bannercardigan` | Banner-front cardigan | rare | Career goal k12 | slot |
| Outfit | `outfit.goal.laurelcoat` | Laurel-trim coat | rare | Career goal k7 | slot |
| Outfit | `outfit.goal.sealedlapel` | Sealed-lapel jacket | rare | Career goal k24 | slot |
| Outfit | `outfit.goal.trophyblazer` | Trophy-room blazer | rare | Career goal k10 | slot |
| Outfit | `outfit.kimono` | Silk robe | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.leather` | Leather jacket | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.manager` | Manager shirt | rare | Level 7 | slot |
| Outfit | `outfit.navypin` | Navy pinstripe | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.pinstripe` | Pinstripe suit | rare | Level 20 | slot |
| Outfit | `outfit.rank.entrepreneur` | Entrepreneur's blazer | rare | Rank 4 | slot |
| Outfit | `outfit.rank.executive` | Executive power suit | rare | Rank 5 | slot |
| Outfit | `outfit.rank.merchant` | Merchant's frock coat | rare | Rank 3 | slot |
| Outfit | `outfit.redpower` | Power red blazer | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.s1.cash` | Cash keeper blazer | rare | Season 1 pass, tier 11, premium | slot |
| Outfit | `outfit.s1.moss` | Moss knit | rare | Season 1 pass, tier 1, premium | slot |
| Outfit | `outfit.s1.plus` | Plus season coat | rare | Season 1 pass, tier 6, premium | slot |
| Outfit | `outfit.s1.rose` | Rose silk jacket | rare | Season 1 pass, tier 12, premium | slot |
| Outfit | `outfit.s2.lilac` | Lilac blouse | rare | Season 2 pass, tier 12, premium (hidden until it starts) | slot |
| Outfit | `outfit.s2.mint` | Mint cardigan | rare | Season 2 pass, tier 1, premium (hidden until it starts) | slot |
| Outfit | `outfit.s2.plus` | Spring plus jacket | rare | Season 2 pass, tier 6, premium (hidden until it starts) | slot |
| Outfit | `outfit.skijacket` | Ski jacket | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.suit` | Suit and tie | rare | Level 5 | slot |
| Outfit | `outfit.threepiece` | Tailored three-piece | rare | Level 40 | slot |
| Outfit | `outfit.trench` | Trench coat | rare | Level 12 | slot |
| Outfit | `outfit.turtleneck` | Turtleneck | rare | Level 10 | slot |
| Outfit | `outfit.tux` | Dinner jacket | rare | Level 25 | slot |
| Outfit | `outfit.tweed` | Autumn tweed | rare | Store 35 gold, boxes | slot |
| Outfit | `outfit.vest` | Waistcoat | rare | Level 15 | slot |
| Outfit | `outfit.boardroom` | Boardroom black | epic | Store 80 gold, boxes | slot |
| Outfit | `outfit.brocade` | Brocade jacket | epic | Level 85 | slot |
| Outfit | `outfit.cashmere` | Cashmere wrap coat | epic | Level 75 | slot |
| Outfit | `outfit.chalkstripe` | Banker's chalk-stripe | epic | Store 80 gold, boxes | slot |
| Outfit | `outfit.evening` | Midnight evening suit | epic | Store 80 gold, boxes | slot |
| Outfit | `outfit.goal.crestblazer` | Crest-badge blazer | epic | Career goal k20 | slot |
| Outfit | `outfit.goal.crowncollar` | Crowned-collar coat | epic | Career goal k16 | slot |
| Outfit | `outfit.goal.diamondjacket` | Diamond-button jacket | epic | Career goal k14 | slot |
| Outfit | `outfit.goal.skylinesuit` | Skyline-print suit | epic | Career goal k18 | slot |
| Outfit | `outfit.goldthread` | Gold-thread suit | epic | Level 95 | slot |
| Outfit | `outfit.holiday` | Holiday sweater | epic | Store 80 gold, boxes | slot |
| Outfit | `outfit.mandarin` | Mandarin collar suit | epic | Level 70 | slot |
| Outfit | `outfit.opera` | Opera cape | epic | Level 80 | slot |
| Outfit | `outfit.pirate` | Pirate frock | epic | Store 80 gold, boxes | slot |
| Outfit | `outfit.racing` | Racing suit | epic | Store 80 gold, boxes | slot |
| Outfit | `outfit.rank.magnate` | Magnate's long coat | epic | Rank 6 | slot |
| Outfit | `outfit.rank.mogul` | Mogul's fur-collar coat | epic | Rank 7 | slot |
| Outfit | `outfit.s1.dusk` | Dusk velvet jacket | epic | Season 1 pass, tier 17, premium | slot |
| Outfit | `outfit.s1.finisher` | Season finisher jacket | epic | Season 1 pass, tier 30, free | slot |
| Outfit | `outfit.s1.ocean` | Ocean captain's coat | epic | Season 1 pass, tier 27, premium | slot |
| Outfit | `outfit.s2.fairday` | Fair-day coat | epic | Season 2 pass, tier 30, free (hidden until it starts) | slot |
| Outfit | `outfit.smoking` | Velvet smoking jacket | epic | Store 80 gold, boxes | slot |
| Outfit | `outfit.velvet` | Velvet blazer | epic | Level 65 | slot |
| Outfit | `outfit.whitetux` | White dinner jacket | epic | Level 90 | slot |
| Outfit | `outfit.astronaut` | Astronaut suit | legendary | Boxes | slot |
| Outfit | `outfit.diamondtux` | Diamond-studded tux | legendary | Boxes | slot |
| Outfit | `outfit.lame` | Gold lame dinner jacket | legendary | Boxes | slot |
| Outfit | `outfit.minkcoat` | Mink-collar coat | legendary | Boxes | slot |
| Outfit | `outfit.rank.tycoon` | Tycoon's crown suit | legendary | Rank 8 | slot |
| Outfit | `outfit.s1.crown` | Season 1 crown robe | legendary | Season 1 pass, tier 30, premium | slot |
| Outfit | `outfit.s2.crown` | Spring crown robe | legendary | Season 2 pass, tier 30, premium (hidden until it starts) | slot |
| Outfit | `outfit.tailcoat` | Tycoon's tailcoat | legendary | Level 100 | slot |
| Face | `face.0` | Calm | common | Free | slot |
| Face | `face.1` | Friendly | common | Free | slot |
| Face | `face.10` | Sleepy | common | Store 15 gold, boxes | slot |
| Face | `face.2` | Warm | common | Free | slot |
| Face | `face.3` | Bright | common | Free | slot |
| Face | `face.4` | Sharp | common | Free | slot |
| Face | `face.5` | Bold | common | Free | slot |
| Face | `face.6` | Wry | common | Free | slot |
| Face | `face.7` | Kind | common | Free | slot |
| Face | `face.8` | Cheerful | common | Store 15 gold, boxes | slot |
| Face | `face.9` | Serious | common | Store 15 gold, boxes | slot |
| Face | `face.11` | Playful | rare | Store 35 gold, boxes | slot |
| Face | `face.12` | Confident | rare | Store 35 gold, boxes | slot |
| Face | `face.13` | Thoughtful | rare | Store 35 gold, boxes | slot |
| Face | `face.14` | Stern | epic | Store 80 gold, boxes | slot |
| Face | `face.15` | Gentle | epic | Store 80 gold, boxes | slot |
| Hair | `hair.bald` | None | common | Free | slot |
| Hair | `hair.bob` | Bob | common | Store 15 gold, boxes | slot |
| Hair | `hair.braids` | Braids | common | Store 15 gold, boxes | slot |
| Hair | `hair.bun` | Bun | common | Free | slot |
| Hair | `hair.buzz` | Buzz | common | Free | slot |
| Hair | `hair.curly` | Curly | common | Free | slot |
| Hair | `hair.long` | Long | common | Free | slot |
| Hair | `hair.pompadour` | Pompadour | common | Store 15 gold, boxes | slot |
| Hair | `hair.short` | Short | common | Free | slot |
| Hair | `hair.side` | Side part | common | Free | slot |
| Hair | `hair.tail` | Ponytail | common | Free | slot |
| Hair | `hair.waves` | Soft waves | common | Store 15 gold, boxes | slot |
| Hair | `hair.afro` | Afro | rare | Store 35 gold, boxes | slot |
| Hair | `hair.topknot` | Top knot | rare | Store 35 gold, boxes | slot |
| Hair | `hair.undercut` | Undercut | rare | Store 35 gold, boxes | slot |
| Hair | `hair.pixie` | Pixie cut | epic | Store 80 gold, boxes | slot |
| Hair | `hair.slicked` | Slicked back | epic | Store 80 gold, boxes | slot |
| Hair | `hair.mohawk` | Mohawk | legendary | Boxes | slot |
| Skin tone | `skin.brown` | Brown | common | Free | slot |
| Skin tone | `skin.deep` | Deep brown | common | Free | slot |
| Skin tone | `skin.fair` | Fair | common | Free | slot |
| Skin tone | `skin.light` | Light | common | Free | slot |
| Skin tone | `skin.olive` | Olive | common | Free | slot |
| Skin tone | `skin.porcelain` | Porcelain | common | Free | slot |
| Skin tone | `skin.sand` | Sand | common | Free | slot |
| Skin tone | `skin.tan` | Tan | common | Free | slot |
| Backdrop | `backdrop.dawn` | Dawn backdrop | common | Season 1 pass, tier 5, premium | file |
| Backdrop | `backdrop.harbour` | Harbour backdrop | common | Season 1 pass, tier 21, premium | file |
| Backdrop | `backdrop.sand` | Sand backdrop | common | Season 1 pass, tier 23, free | file |
| Backdrop | `gold.backdrop.brickloft` | Brick loft | common | Store 15 gold, boxes | slot |
| Backdrop | `gold.backdrop.cafeterrace` | Cafe terrace | common | Store 15 gold, boxes | slot |
| Backdrop | `gold.backdrop.fog` | Fog | common | Store 15 gold, boxes | file |
| Backdrop | `gold.backdrop.greenhouse` | Greenhouse | common | Store 15 gold, boxes | slot |
| Backdrop | `gold.backdrop.harbourdusk` | Harbour at dusk | common | Store 15 gold, boxes | slot |
| Backdrop | `gold.backdrop.paperwhite` | Paper white | common | Store 15 gold, boxes | slot |
| Backdrop | `gold.backdrop.pine` | Pine forest | common | Store 15 gold, boxes | slot |
| Backdrop | `gold.backdrop.sandstone` | Sandstone | common | Store 15 gold, boxes | slot |
| Backdrop | `gold.backdrop.slate` | Slate wall | common | Store 15 gold, boxes | slot |
| Backdrop | `backdrop.orchard` | Orchard backdrop | rare | Season 2 pass, tier 23, free (hidden until it starts) | slot |
| Backdrop | `backdrop.pastel` | Pastel backdrop | rare | Season 2 pass, tier 5, premium (hidden until it starts) | slot |
| Backdrop | `gold.backdrop.citynight` | City at night | rare | Store 35 gold, boxes | slot |
| Backdrop | `gold.backdrop.desert` | Desert noon | rare | Store 35 gold, boxes | slot |
| Backdrop | `gold.backdrop.library` | Old library | rare | Store 35 gold, boxes | slot |
| Backdrop | `gold.backdrop.lighthouse` | Lighthouse coast | rare | Store 35 gold, boxes | slot |
| Backdrop | `gold.backdrop.marketsquare` | Market square | rare | Store 35 gold, boxes | slot |
| Backdrop | `gold.backdrop.orchardrow` | Orchard rows | rare | Store 35 gold, boxes | slot |
| Backdrop | `gold.backdrop.plum` | Plum | rare | Store 35 gold, boxes | file |
| Backdrop | `gold.backdrop.rainwindow` | Rain on glass | rare | Store 35 gold, boxes | slot |
| Backdrop | `gold.backdrop.snowpeaks` | Snow peaks | rare | Store 35 gold, boxes | slot |
| Backdrop | `backdrop.dawn.s2` | Spring dawn backdrop | epic | Season 2 pass, tier 21, premium (hidden until it starts) | slot |
| Backdrop | `gold.backdrop.aurora` | Aurora | epic | Store 80 gold, boxes | file |
| Backdrop | `gold.backdrop.cherrygarden` | Garden in bloom | epic | Store 80 gold, boxes | slot |
| Backdrop | `gold.backdrop.marbleatrium` | Marble atrium | epic | Store 80 gold, boxes | slot |
| Backdrop | `gold.backdrop.rooftopdusk` | Rooftop at dusk | epic | Store 80 gold, boxes | slot |
| Backdrop | `gold.backdrop.skyline` | Skyline penthouse | epic | Store 80 gold, boxes | slot |
| Backdrop | `gold.backdrop.vaultdoor` | Vault door | epic | Store 80 gold, boxes | slot |
| Backdrop | `gold.coll.harbour` | Harbour Lights | epic | Collection reward | file |
| Backdrop | `gold.coll.spring` | Spring Fair | epic | Collection reward (hidden until season 2) | slot |
| Backdrop | `gold.backdrop.crystalcave` | Crystal cave | legendary | Boxes | slot |
| Backdrop | `gold.backdrop.goldhall` | Gilded hall | legendary | Boxes | slot |
| Backdrop | `gold.backdrop.nebula` | Nebula | legendary | Boxes | slot |
| Backdrop | `gold.backdrop.opera` | Opera house | legendary | Boxes | slot |
| Name plate | `gold.plate.chalk` | Chalkboard | common | Store 15 gold, boxes | slot |
| Name plate | `gold.plate.pewter` | Pewter plate | common | Store 15 gold, boxes | file |
| Name plate | `gold.plate.ribbon` | Ribbon | common | Store 15 gold, boxes | slot |
| Name plate | `gold.plate.tape` | Label tape | common | Store 15 gold, boxes | slot |
| Name plate | `gold.plate.woodsign` | Wooden sign | common | Store 15 gold, boxes | slot |
| Name plate | `plate.brass` | Brass plate | common | Season 1 pass, tier 13, free | file |
| Name plate | `plate.ledger` | Ledger plate | common | Season 1 pass, tier 3, free | file |
| Name plate | `plate.marble` | Marble plate | common | Season 1 pass, tier 24, premium | file |
| Name plate | `plate.walnut` | Walnut plate | common | Season 1 pass, tier 2, premium | file |
| Name plate | `gold.plate.brassplaque` | Brass plaque | rare | Store 35 gold, boxes | slot |
| Name plate | `gold.plate.copper` | Copper plate | rare | Store 35 gold, boxes | file |
| Name plate | `gold.plate.enamel` | Enamel sign | rare | Store 35 gold, boxes | slot |
| Name plate | `gold.plate.slate` | Slate tile | rare | Store 35 gold, boxes | slot |
| Name plate | `plate.egg` | Painted-egg plate | rare | Season 2 pass, tier 2, premium (hidden until it starts) | slot |
| Name plate | `gold.coll.counting` | Counting House plate | epic | Collection reward | file |
| Name plate | `gold.plate.carbon` | Carbon fibre | epic | Store 80 gold, boxes | slot |
| Name plate | `gold.plate.marbleslab` | Marble slab | epic | Store 80 gold, boxes | slot |
| Name plate | `gold.plate.neonbar` | Neon bar | epic | Store 80 gold, boxes | slot |
| Name plate | `gold.plate.onyx` | Onyx plate | epic | Store 80 gold, boxes | file |
| Name plate | `plate.marble.s2` | Marble-and-blossom plate | epic | Season 2 pass, tier 24, premium (hidden until it starts) | slot |
| Name plate | `gold.plate.leaf` | Gold leaf | legendary | Boxes | file |
| Name plate | `gold.plate.mosaic` | Glass mosaic | legendary | Boxes | slot |
| Flair | `flair.crest` | Rich-list crest | common | Season 1 pass, tier 15, premium | file |
| Flair | `gold.flair.laurel` | Rich-list laurel | rare | Store 35 gold, boxes | file |
| Flair | `gold.flair.pennant` | Pennant | rare | Store 35 gold, boxes | slot |
| Flair | `gold.flair.plus` | Plus star | rare | Ledger plan | slot |
| Flair | `gold.flair.spark` | Sparkle | rare | Store 35 gold, boxes | slot |
| Flair | `flair.egg` | Painted-egg flair | epic | Season 2 pass, tier 15, premium (hidden until it starts) | slot |
| Flair | `gold.coll.archive` | Archive seal | epic | Collection reward | file |
| Flair | `gold.flair.coinrain` | Coin rain | epic | Store 80 gold, boxes | slot |
| Flair | `gold.flair.comet` | Comet | epic | Store 80 gold, boxes | slot |
| Flair | `gold.flair.crown` | Crown | epic | Store 80 gold, boxes | slot |
| Flair | `gold.flair.ember` | Ember | epic | Store 80 gold, boxes | slot |
| Flair | `gold.flair.ink` | Ink flourish | epic | Store 80 gold, boxes | slot |
| Flair | `gold.flair.laurelgold` | Gold laurel | epic | Store 80 gold, boxes | slot |
| Flair | `gold.flair.signet` | Signet ring | epic | Store 80 gold, boxes | slot |
| Flair | `gold.flair.aurora` | Aurora ribbon | legendary | Boxes | slot |
| Flair | `gold.flair.diamond` | Diamond | legendary | Boxes | slot |
| Flair | `gold.flair.dragon` | Gold dragon | legendary | Boxes | slot |
| Flair | `gold.flair.founder` | Founder laurel | legendary | Ledger plan | slot |
| Flair | `gold.flair.galaxy` | Galaxy | legendary | Boxes | slot |
| Flair | `gold.flair.hallofame` | Hall of fame star | legendary | Boxes | slot |
| Flair | `gold.flair.phoenix` | Phoenix | legendary | Boxes | slot |
| Flair | `gold.flair.sun` | Rich-list sun | legendary | Boxes | file |
| Flair | `gold.flair.vault` | Vault seal | legendary | Boxes | slot |
| Trade plate | `gold.trade.pewter` | Pewter trade plate | common | Store 15 gold, boxes | file |
| Trade plate | `trade.engraved` | Engraved trade plate | common | Season 1 pass, tier 9, premium | file |
| Trade plate | `trade.gilded` | Gilded trade plate | common | Season 1 pass, tier 28, premium | file |
| Trade plate | `trade.market` | Market-stall plate | rare | Season 2 pass, tier 9, premium (hidden until it starts) | slot |
| Trade plate | `gold.coll.market` | Market Square trade plate | epic | Collection reward | file |
| Trade plate | `gold.trade.rose` | Rose trade plate | epic | Store 80 gold, boxes | file |
| Trade plate | `trade.gilded.s2` | Gilded-hare plate | epic | Season 2 pass, tier 28, premium (hidden until it starts) | slot |
| Save slot | `gold.slot.1` | Extra save slot | common | Store 15 gold, boxes | file |
| Save slot | `gold.slot.2` | Second extra save slot | common | Store 15 gold, boxes | file |
| Save slot | `gold.slot.3` | Third extra save slot | common | Store 15 gold, boxes | file |
| Advisor line | `advisor.horizon` | Advisor: look further | common | Season 1 pass, tier 18, premium | file |
| Advisor line | `advisor.patience` | Advisor: patience pays | common | Season 1 pass, tier 3, premium | file |
| Advisor line | `advisor.s2.market` | Advisor: fair day | common | Season 2 pass, tier 3, premium (hidden until it starts) | slot |
| Advisor line | `advisor.s2.patience` | Advisor: slow growth | common | Season 2 pass, tier 17, premium (hidden until it starts) | slot |
| Advisor line | `advisor.s2.spring` | Advisor: spring clean | common | Season 2 pass, tier 13, free (hidden until it starts) | slot |

233 items: outfit 95, face 16, hair 18, skin tone 8, backdrop 36, name plate 22, flair 23, trade plate 7, save slot 3, advisor line 5.

## Vehicles: model name and picture

Each picture carries exactly one model name. Fleet offers use `vehicle_art.json`; a vehicle model's offer number n takes the picture at n modulo its list. A picture key is a cell of the items sheet; `vehicle.*` keys have no picture yet (placeholder).

| Picture key | Model name | Used by vehicle models |
|---|---|---|
| `van_box` | Moverra 20 | `van_s`, `van_box` |
| `van_box_var` | Moverra 20 Plus | `van_s`, `van_box` |
| `van_box_v2` | Moverra 20 Eco | `van_s`, `van_box` |
| `van_l` | Transvia L | `van_l` |
| `van_l_var` | Transvia L Plus | `van_l` |
| `van_l_v2` | Transvia L Eco | `van_l` |
| `ev_van` | Voltvan E | `ev_van` |
| `ev_van_var` | Voltvan E Plus | `ev_van` |
| `ev_van_v2` | Voltvan E Eco | `ev_van` |
| `delivery_van_ev` | Voltvan Delivery | `ev_van` |
| `pickup` | Ridgeback 4x4 | `pickup` |
| `car_compact` | Pico 1.0 | `car_s` |
| `car_estate` | Lyra Estate | `car_s`, `taxi_ev` |
| `car_suv` | Orsa Cross | `car_ev` |
| `car_luxury` | Regent Sedan | `car_lux` |
| `limousine` | Regent Limo | `car_lux` |
| `taxi_cmf_var` | Cabra Hybrid Plus | `taxi_ev`, `taxi_cmf` |
| `taxi_cmf` | Cabra Hybrid | `taxi_cmf` |
| `taxi_cmf_v2` | Cabra Hybrid Eco | `taxi_cmf` |
| `taxi_prm` | Executive One | `taxi_prm` |
| `taxi_prm_var` | Executive One Plus | `taxi_prm` |
| `taxi_prm_v2` | Executive One Eco | `taxi_prm` |
| `taxi_xl` | Cabra XL | `taxi_xl` |
| `taxi_xl_var` | Cabra XL Plus | `taxi_xl` |
| `taxi_xl_v2` | Cabra XL Eco | `taxi_xl` |
| `minibus` | Shuttle 16 | `minibus` |
| `minibus_var` | Shuttle 16 Plus | `minibus` |
| `minibus_v2` | Shuttle 16 Eco | `minibus` |
| `bus` | Citara 12 | `bus` |
| `bus_var` | Citara 12 Plus | `bus` |
| `bus_v2` | Citara 12 Eco | `bus` |
| `truck_s` | Haulmark 12 | `truck_s` |
| `truck_s_var` | Haulmark 12 Plus | `truck_s` |
| `truck_s_v2` | Haulmark 12 Eco | `truck_s` |
| `truck_h` | Haulmark 40 | `truck_h` |
| `truck_h_var` | Haulmark 40 Plus | `truck_h` |
| `truck_h_v2` | Haulmark 40 Eco | `truck_h` |
| `truck_ev` | Haulmark E | `truck_ev` |
| `truck_ev_var` | Haulmark E Plus | `truck_ev` |
| `truck_ev_v2` | Haulmark E Eco | `truck_ev` |
| `bike` | Cargo Bike | `bike` |
| `bike_var` | Cargo Bike Plus | `bike` |
| `bike_v2` | Cargo Bike Eco | `bike` |
| `scooter` | Courier Scooter | `scooter` |
| `scooter_var` | Courier Scooter Plus | `scooter` |
| `scooter_v2` | Courier Scooter Eco | `scooter` |
| `excav` | Digmaster 14 | `excav` |
| `excav_var` | Digmaster 14 Plus | `excav` |
| `excav_v2` | Digmaster 14 Eco | `excav` |
| `crane` | Liftmaster | `crane` |
| `crane_var` | Liftmaster Plus | `crane` |
| `crane_v2` | Liftmaster Eco | `crane` |
| `foodtruck` | Galley Truck | `foodtruck` |
| `foodtruck_var` | Galley Truck Plus | `foodtruck` |
| `foodtruck_v2` | Galley Truck Eco | `foodtruck` |
| `vehicle.ship_s` (placeholder) | Coaster 4200 | `ship_s` |
| `vehicle.ship_l` (placeholder) | Bulker 60 | `ship_l` |
| `vehicle.ferry` (placeholder) | Ferry 400 | `ferry` |
| `vehicle.plane_s` (placeholder) | Turboprop 70 | `plane_s` |

Luxury cars, yachts and jets (`luxury.json`, field `art` = sheet/cell):

| Id | Model | Category | Picture |
|---|---|---|---|
| `c15` | Hyperion Zenith Tourer | cars | `cars/b2-2` |
| `c1` | Aurelion S saloon | cars | `cars/b2-1` |
| `c11` | Bavaria 8 Apex coupé | cars | `cars/b1-3` |
| `c10` | Apex V10 GT | cars | `cars/b1-2` |
| `c7` | Vanguard Artemis | cars | `cars/b1-1` |
| `c8` | Vanguard Sovereign GT | cars | `cars/b6-3` |
| `c9` | Vanguard Sovereign GT Black Edition | cars | `cars/b6-2` |
| `c2` | Brandt 912 GT RS | cars | `cars/b5-1` |
| `c4` | Ravenna Tempesta | cars | `cars/b3-1` |
| `c3` | Aurelion GT Noir | cars | `cars/b3-2` |
| `c14` | Hyperion Zenith One | cars | `cars/b7-3` |
| `c13` | Apex Apexian SUV | cars | `cars/b3-3` |
| `c12` | Monarch Regent limousine | cars | `cars/b4-1` |
| `c5` | Halvorsen Hyper 99 | cars | `cars/b7-1` |
| `c6` | Ravenna Fulmine 63 | cars | `cars/b5-2` |
| `y1` | Sundqvist 40 day cruiser | yachts | `luxury/yachtjet-3` |
| `y2` | Marenco 80 motor yacht | yachts | `luxury/yachtjet-2` |
| `y3` | Halcyon 50 m superyacht | yachts | `luxury/yachtjet-1` |
| `j1` | Corvane Light 4 jet | jets | `luxury/homes-1` |
| `j2` | Stratos Noir midsize jet | jets | `luxury/yachtjet-6` |
| `j4` | Aerion Long Range 650 | jets | `luxury/yachtjet-5` |
| `j3` | Stratos Global 8000 jet | jets | `luxury/yachtjet-4` |
| `j5` | Zephyr Celestia Grand | jets | none yet (placeholder) |
