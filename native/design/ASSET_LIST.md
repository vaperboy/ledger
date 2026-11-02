# Missing assets and variations (for image generation)

## Gemini prompt (reuse for every sheet: change only the SUBJECT line)

Create ONE square image, exactly 2048 x 2048 px, as a grid of 4 columns by 4 rows (16 cells, 512 x 512 px each), no gaps, no borders, no text except the label strip below each cell.

SUBJECT: [replace with the list for this sheet, e.g. "minibus, city bus, distribution truck, tractor trailer, electric truck, cargo bike, scooter, excavator, crane, food truck, ship, ferry, small plane, taxi"]

STYLE (all cells, must match exactly):
- Photorealistic, neutral overcast daylight, eye-level three-quarter view, centred subject filling about 70% of the cell.
- Plain, slightly out-of-focus neutral background (grey asphalt or pale sky). No people, no logos, no readable brand names, no number plates (use blank plates).
- Muted, desaturated colours; one accent colour per cell allowed. Consistent camera height and lens across the whole grid.
- Subject and cell count must match the SUBJECT list. If there are fewer items than 16, leave the remaining cells empty grey.

LABELS: beneath each cell, a dark strip 40 px high with the item key in white, small sans-serif text, exactly as written in the SUBJECT list (e.g. "bus_city").

OUTPUT: a single PNG or JPEG, 2048 x 2048, no watermark.

## Priority list (16-cell sheets; each cell = one asset)

### Sheet V1: vehicles without a photo (TechPro, Vehicles)
bus, minibus, truck_s (distribution 12 t), truck_h (tractor + trailer), truck_ev, van_box, van_l, ev_van, bike (cargo e-bike), scooter, foodtruck, taxi_xl, taxi_cmf, taxi_prm, excav (excavator), crane
Also needed: ship_s, ship_l, ferry, plane_s (these may stay as icons).

### Sheet P1: premises (AirStay listings), 2 variants per type
kitchen (restaurant), industrial hall, warehouse, clinic, gym hall, hotel building, yard/lot, mountain land (slope), shop (2 extra), office (2 extra)
Each cell: interior OR exterior, daylight, no people.

### Sheet E1: equipment kinds (TechPro)
laptop (cons), tutor tablet (tutor), car cleaning machine (carclean), camera and lens (photo), handyman tool kit (handy), cleaning machine (cleaning), desk setup (webdev), marketing screen (mktg), office furniture (furniture), bakery oven (bakery), brewery tanks (brewery), farm tractor (farm), fishing gear (salmon), hair salon chair (barber), dental chair (dental), kiosk counter (kiosk)

### Sheet E2: equipment kinds (TechPro), second batch
restaurant kitchen line (restaurant), nightclub lights (nightclub), gym machines (gym), hotel bed (hotel), casino table (casino), ski equipment (skires), electrician tools (electrician), plumber tools (plumber), construction tools (construction), security camera (security), server rack (webshop), grocery fridge (grocery), hardware shelf (hardware), pet grooming (pets), physio table (physio), factory machine (factory)

### Sheet I1: insurance hero and cards (Atlas)
home building hero (1), car insurance card (1), business property card (1), liability card (1), fleet card (1), workers card (1), cyber card (1), travel card (1), and 8 extra cells in matching style for future policies.

### Sheet S1: software categories (TechPro, Software)
cloud (cloud), licence (lic), subscription box (sub), developer laptop (sw), accounting software (acct), CRM dashboard (crm), design tablet (design), e-commerce screen (shop), POS terminal (pos), email icon (mail), security shield (shield), backup drive (backup), video editing (edit), mobile app phone (app), analytics chart (chart), helpdesk headset (help)

## Variations rule
- Every category used in the game needs at least 3 different pictures so two neighbouring listings never match.
- Reuse the same sheet for different variants by changing only the SUBJECT line (e.g. "office interior, variant 1-16").

## Cost notes
- One 2048 sheet = 16 assets, so a full set of about 130 assets is about 9 sheets.
- Keep one generation per sheet; regenerate only the failed cell by re-prompting with the cell number.
- Mark each output file as `sheetname_cellNN.png` after cutting (cut 512 px cells, keep labels for checking).
