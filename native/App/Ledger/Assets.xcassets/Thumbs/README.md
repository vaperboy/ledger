# Thumbnails: which pictures the game can show

Drop a picture into the matching folder as an image set and the game uses it in place of the icon circle. Until then nothing changes.

## Naming convention

Image set name: `thumb-<kind>-<key>` (lower case; keys below are the engine ids, already in this form). Shown as a circle or rounded square, so supply a **square** picture, 256 x 256 px (@1x 128, @2x 256, @3x 384 if you supply all three), subject centred with some margin (the corners are cropped for the circle).

| Kind | Asset name | Where it shows |
|---|---|---|
| Premises | `thumb-premises-<premises kind>` | new-company premises options, Find a workshop/office |
| Person role | `thumb-person-<role id>` | people cards, hiring and candidate cards |
| Trade (company) | `thumb-trade-<trade id>` | company rows on Home, Group, chains, Bank accounts |
| Luxury item | `thumb-luxury-<item id>` | Aurum shop list, collection list, item detail |

The code that builds these names is `ThumbnailView.assetName` in `Design/ThumbnailView.swift`.

## Employee faces (faces sheet)

People who work in companies (managers, assistants, staff, candidates and applicants, Team lists, staff profile) show a face cut from one sheet, `Resources/faces-sheet.jpg` (a bundled resource, not an image set): 15 columns x 9 rows = 135 portraits. `Design/FaceSheet.swift` slices it at runtime (centred square of each cell, cached) and holds the tag table (gender, age band, region per cell). A face is picked deterministically from the person's gender (derived from the first name in the engine, `Employees/FaceTraits.swift`), age band and the country of their company; people of one company get different cell and variant pairs where possible. Variants of a cell: mirrored, closer offset crop, and mirrored + closer with a mild warm grade. The player, rivals, the rich list, companies, premises and luxury items do not get faces. If the sheet cannot be loaded the initials circle shows, and a `thumb-person-<role>` image set is used only where no face is requested. To replace the sheet keep the file name, the 15 x 9 grid and the cell order.

## Premises kinds (11)

`thumb-premises-home`, `thumb-premises-office`, `thumb-premises-shop`, `thumb-premises-kitchen`, `thumb-premises-industrial`, `thumb-premises-warehouse`, `thumb-premises-hotel`, `thumb-premises-clinic`, `thumb-premises-yard`, `thumb-premises-gym`, `thumb-premises-slope`

## Person roles

Workers (`tables.ROLES`, 97):

| Key | Role |
|---|---|
| `thumb-person-helper` | General helper |
| `thumb-person-cleaner` | Cleaner |
| `thumb-person-cashier` | Shop assistant |
| `thumb-person-waiter` | Waiter / server |
| `thumb-person-cook` | Cook |
| `thumb-person-chef` | Head chef |
| `thumb-person-barista` | Barista |
| `thumb-person-baker` | Baker |
| `thumb-person-bartender` | Bartender |
| `thumb-person-guard` | Security guard |
| `thumb-person-recept` | Receptionist |
| `thumb-person-housek` | Housekeeper |
| `thumb-person-trainer` | Personal trainer |
| `thumb-person-physio` | Physiotherapist |
| `thumb-person-lawyer` | Lawyer |
| `thumb-person-paralegal` | Paralegal |
| `thumb-person-acct` | Accountant |
| `thumb-person-dev` | Developer |
| `thumb-person-designer` | Designer |
| `thumb-person-marketer` | Marketer |
| `thumb-person-sales` | Salesperson |
| `thumb-person-consult` | Consultant |
| `thumb-person-carp` | Carpenter |
| `thumb-person-elec` | Electrician |
| `thumb-person-plumb` | Plumber |
| `thumb-person-labour` | Construction worker |
| `thumb-person-foreman` | Site foreman |
| `thumb-person-engineer` | Engineer |
| `thumb-person-architect` | Architect |
| `thumb-person-operator` | Machine operator |
| `thumb-person-fworker` | Factory worker |
| `thumb-person-farmh` | Farm hand |
| `thumb-person-fishtech` | Fish-farm technician |
| `thumb-person-dealer` | Casino dealer |
| `thumb-person-cardealer` | Car salesperson |
| `thumb-person-mech` | Mechanic |
| `thumb-person-underw` | Underwriter |
| `thumb-person-claims` | Claims handler |
| `thumb-person-banker` | Bank advisor |
| `thumb-person-credit` | Credit analyst |
| `thumb-person-analyst` | Fund analyst |
| `thumb-person-propm` | Property manager |
| `thumb-person-caretaker` | Caretaker |
| `thumb-person-windtech` | Energy technician |
| `thumb-person-geo` | Geologist |
| `thumb-person-offshore` | Offshore operator |
| `thumb-person-instr` | Driving instructor |
| `thumb-person-estate` | Estate agent |
| `thumb-person-ittech` | IT technician |
| `thumb-person-hr` | HR advisor |
| `thumb-person-analyst2` | Data analyst |
| `thumb-person-av` | AV / sound tech |
| `thumb-person-event` | Event coordinator |
| `thumb-person-driver` | Taxi driver |
| `thumb-person-truckd` | Truck driver |
| `thumb-person-courier` | Courier |
| `thumb-person-pilot` | Pilot |
| `thumb-person-fo` | First officer |
| `thumb-person-cabin` | Cabin crew |
| `thumb-person-deckh` | Deck officer |
| `thumb-person-seaman` | Seaman |
| `thumb-person-groom` | Groomer / carer |
| `thumb-person-barber` | Hair stylist |
| `thumb-person-tutor` | Tutor |
| `thumb-person-photog` | Photographer |
| `thumb-person-handy` | Handyman |
| `thumb-person-carwash` | Car detailer |
| `thumb-person-hm` | Hotel manager |
| `thumb-person-pm` | Project manager |
| `thumb-person-buyer` | Buyer / purchaser |
| `thumb-person-driverB` | Bus driver |
| `thumb-person-teller` | Bank teller |
| `thumb-person-compl` | Compliance officer |
| `thumb-person-agent` | Insurance agent |
| `thumb-person-broker` | Broker / trader |
| `thumb-person-dispatch` | Dispatcher |
| `thumb-person-tech` | Technician |
| `thumb-person-waiterB` | Bar staff |
| `thumb-person-dj` | Booker / DJ |
| `thumb-person-usher` | Usher / floor staff |
| `thumb-person-projc` | Project coordinator |
| `thumb-person-safety` | Safety officer (workplace safety) |
| `thumb-person-lab` | Quality / lab tech |
| `thumb-person-shipm` | Ship captain |
| `thumb-person-eng` | Ship / plant engineer |
| `thumb-person-chefP` | Pastry / production lead |
| `thumb-person-butcher` | Butcher / fish cutter |
| `thumb-person-whw` | Warehouse worker |
| `thumb-person-liftop` | Lift operator |
| `thumb-person-skiinst` | Ski instructor |
| `thumb-person-snowtech` | Snowmaker and groomer driver |
| `thumb-person-dentist` | Dentist |
| `thumb-person-dentnurse` | Dental nurse |
| `thumb-person-vintner` | Winemaker |
| `thumb-person-rentag` | Rental agent |
| `thumb-person-lead` | Shift lead |
| `thumb-person-mktan` | Market analyst |

Manager types (`tables.MGR_TYPES`; a company's manager is also `thumb-person-manager`, the assistant `thumb-person-assistant-manager`):

| Key | Role |
|---|---|
| `thumb-person-gen` | General manager |
| `thumb-person-ops` | Operations manager |
| `thumb-person-host` | Hospitality manager |
| `thumb-person-site` | Site / construction manager |
| `thumb-person-sales` | Sales-driven manager |
| `thumb-person-tech` | Technical manager |
| `thumb-person-fin` | Financial / compliance manager |
| `thumb-person-ind` | Industrial plant manager |
| `thumb-person-fleet` | Fleet and logistics manager |
| `thumb-person-prop` | Property manager |
| `thumb-person-fund` | Investment manager |
| `thumb-person-energy` | Energy / asset manager |
| `thumb-person-pro` | Professional-services partner |
| `thumb-person-retail` | Retail manager |
| `thumb-person-game` | Gaming and licence manager |
| `thumb-person-clin` | Clinical lead |

Group head-office roles (`tables.HQ_ROLES`):

| Key | Role |
|---|---|
| `thumb-person-pa` | Personal assistant |
| `thumb-person-hr` | HR manager |
| `thumb-person-acc` | Group accountant |
| `thumb-person-law` | In-house lawyer |
| `thumb-person-ana` | Data analyst |
| `thumb-person-perf` | Performance analyst |
| `thumb-person-mkt` | Marketing director |
| `thumb-person-proc` | Procurement manager |
| `thumb-person-strat` | Strategy analyst |
| `thumb-person-fin` | Finance manager |

Card titles for management posts that have no id (for example `General manager` becomes `thumb-person-general-manager`): lower case, spaces and punctuation turned into single hyphens.

## Trades (67)

| Key | Trade |
|---|---|
| `thumb-trade-cons` | Freelance consultant |
| `thumb-trade-tutor` | Online tutoring |
| `thumb-trade-carclean` | Mobile car cleaning |
| `thumb-trade-photo` | Photography and video |
| `thumb-trade-handy` | Handyman |
| `thumb-trade-cleaning` | Cleaning company |
| `thumb-trade-webdev` | Software and web agency |
| `thumb-trade-mktg` | Marketing agency |
| `thumb-trade-law` | Law firm |
| `thumb-trade-acctfirm` | Accounting firm |
| `thumb-trade-staffing` | Staffing agency |
| `thumb-trade-barber` | Hair salon |
| `thumb-trade-drivsk` | Driving school |
| `thumb-trade-physio` | Physiotherapy clinic |
| `thumb-trade-estate` | Estate agency |
| `thumb-trade-pets` | Pet daycare and grooming |
| `thumb-trade-carrepair` | Car repair workshop |
| `thumb-trade-foodtruck` | Food truck |
| `thumb-trade-cafe` | Café |
| `thumb-trade-restaurant` | Restaurant |
| `thumb-trade-nightclub` | Bar and nightclub |
| `thumb-trade-gym` | Gym |
| `thumb-trade-hotel` | Hotel (50 rooms) |
| `thumb-trade-casino` | Casino |
| `thumb-trade-fun` | Entertainment centre |
| `thumb-trade-skires` | Ski resort |
| `thumb-trade-indoorski` | Indoor ski hall |
| `thumb-trade-kiosk` | Convenience store |
| `thumb-trade-boutique` | Clothing boutique |
| `thumb-trade-webshop` | Webshop |
| `thumb-trade-grocery` | Supermarket |
| `thumb-trade-hardware` | Building-supplies store |
| `thumb-trade-cardealer` | Vehicle dealership |
| `thumb-trade-construction` | Construction firm |
| `thumb-trade-electrician` | Electrical contractor |
| `thumb-trade-plumber` | Plumbing firm |
| `thumb-trade-realdev` | Real-estate development |
| `thumb-trade-event` | Event and production agency |
| `thumb-trade-engcons` | Engineering and architecture office |
| `thumb-trade-bakery` | Bakery and pastry |
| `thumb-trade-brewery` | Craft brewery |
| `thumb-trade-furniture` | Furniture workshop |
| `thumb-trade-salmon` | Salmon farm |
| `thumb-trade-factory` | Manufacturing factory |
| `thumb-trade-farm` | Farm and forestry |
| `thumb-trade-taxi` | Taxi service |
| `thumb-trade-courier` | Courier and last-mile delivery |
| `thumb-trade-trucking` | Freight trucking |
| `thumb-trade-shipping` | Shipping company |
| `thumb-trade-airline` | Regional airline |
| `thumb-trade-wh3pl` | Warehouse and fulfilment |
| `thumb-trade-resrent` | Residential rentals |
| `thumb-trade-comrent` | Commercial property |
| `thumb-trade-parking` | Parking and self-storage |
| `thumb-trade-insco` | Insurance company |
| `thumb-trade-bank` | Bank |
| `thumb-trade-fund` | Investment fund |
| `thumb-trade-power` | Renewable power producer |
| `thumb-trade-oilgas` | Oil and gas company |
| `thumb-trade-dental` | Dental clinic |
| `thumb-trade-gamestudio` | Game studio |
| `thumb-trade-security` | Private security |
| `thumb-trade-vineyard` | Vineyard and winery |
| `thumb-trade-pcbang` | PC gaming café |
| `thumb-trade-carrental` | Car rental |

## Luxury items (45)

**Cars**

| Key | Item |
|---|---|
| `thumb-luxury-c15` | Hyperion Zenith Tourer |
| `thumb-luxury-c1` | Aurelion S saloon |
| `thumb-luxury-c11` | Bavaria 8 Apex coupé |
| `thumb-luxury-c10` | Apex V10 GT |
| `thumb-luxury-c7` | Vanguard Artemis |
| `thumb-luxury-c8` | Vanguard Sovereign GT |
| `thumb-luxury-c9` | Vanguard Sovereign GT Black Edition |
| `thumb-luxury-c2` | Brandt 912 GT RS |
| `thumb-luxury-c4` | Ravenna Tempesta |
| `thumb-luxury-c3` | Aurelion GT Noir |
| `thumb-luxury-c14` | Hyperion Zenith One |
| `thumb-luxury-c13` | Apex Apexian SUV |
| `thumb-luxury-c12` | Monarch Regent limousine |
| `thumb-luxury-c5` | Halvorsen Hyper 99 |
| `thumb-luxury-c6` | Ravenna Fulmine 63 |

**Watches and jewellery**

| Key | Item |
|---|---|
| `thumb-luxury-w2` | Voltara Éther Chronograph |
| `thumb-luxury-w1` | Aethelred Vanguard Régulateur Grand Feu |
| `thumb-luxury-w5` | Aethelred Monarch Solstice Celestial |
| `thumb-luxury-w3` | Vescovi Rivière diamond necklace |
| `thumb-luxury-w4` | Aethelred Hyperion Horizon Tourbillon |
| `thumb-luxury-w6` | Aethelred Apexian Zenith Split-Seconds |
| `thumb-luxury-w7` | Aethelred Sovereign Astrolabe |
| `thumb-luxury-w8` | Aethelred Aetherius Infinite Complication |

**Art and collectibles**

| Key | Item |
|---|---|
| `thumb-luxury-a1` | Oil painting by Mira Halden |
| `thumb-luxury-a2` | Captain Polar #1, first issue |
| `thumb-luxury-a3` | Château Ormel cellar, 120 bottles |
| `thumb-luxury-a4` | Jules Arnaud print set |
| `thumb-luxury-a5` | Canvas by Otto Brehm |

**Yachts**

| Key | Item |
|---|---|
| `thumb-luxury-y1` | Sundqvist 40 day cruiser |
| `thumb-luxury-y2` | Marenco 80 motor yacht |
| `thumb-luxury-y3` | Halcyon 50 m superyacht |

**Private jets**

| Key | Item |
|---|---|
| `thumb-luxury-j1` | Corvane Light 4 jet |
| `thumb-luxury-j2` | Stratos Noir midsize jet |
| `thumb-luxury-j4` | Aerion Long Range 650 |
| `thumb-luxury-j3` | Stratos Global 8000 jet |
| `thumb-luxury-j5` | Zephyr Celestia Grand |

**Homes**

| Key | Item |
|---|---|
| `thumb-luxury-h3` | Forest pavilion near Kyoto |
| `thumb-luxury-h4` | Basalt house above a black beach |
| `thumb-luxury-h1` | Cliff house on the Big Sur coast |
| `thumb-luxury-h2` | Villa on the Amalfi cliffs |

**Estates**

| Key | Item |
|---|---|
| `thumb-luxury-e4` | Forest and lake, 900 hectares |
| `thumb-luxury-e3` | Highland estate |
| `thumb-luxury-e1` | Hillside vineyard and château |
| `thumb-luxury-e5` | Castle and event venue |
| `thumb-luxury-e2` | Private island |
