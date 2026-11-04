# Wave 7: PROJ and job-contract model (construction, electrician, plumber, handy, engcons, security)

Files: `Businesses/Wave7Jobs.swift`, `Businesses/Resources/wave7_jobs.json`, `Businesses/ItemWave7.swift` (registry, all six trades), `Tests/LedgerTests/Wave7Tests.swift`, app `Features/Companies/Wave7ItemBlocks.swift`.

## Decisions
- A job type is an item: quoted price per job or hour, materials at cost plus markup (`mk`), person-hours and crew (roles from ROLES), vehicle need, lead time before the crew starts, call-out (starts within a day, jumps the backlog) or scheduled job (waits for backlog and lead time), warranty callback rate and months, phases with subcontract share (construction, rewire, bathroom, engineering deliverables), documents (certificates), and recurring plans and contracts (inspection and boiler plans, maintenance, retainers, monitoring, guard hours per site per month: 160 hours per 4 weeks).
- Models: `svc` call-outs and hourly jobs, `proj` quoted jobs, `sub` plans and contracts, `stk` the handyman's tool and materials kit.
- Books do not move. `cost` = materials and subcontractors, scaled on install so the weighted menu equals the books' share: `mat + sub` traits for construction, electrician, plumber (engcons has 0, so its record cost is 0 and the real cost is labour), `cogs` for handy and security. Revenue weights add up to 1 (same normalisation as W6).
- Real cost on the item page slider: `prep` = crew labour (hours x market pay of the crew roles x 12 / (52 x 36) x employer cost 1.2) plus expected warranty callbacks (rate x (0.4 x labour + 0.25 x materials)). Not booked (wages are already in weekly costs). Refreshed weekly at today's pay. A trade is therefore shown honestly per item: a call-out can lose money while a rewire earns.
- Hours scale: the data's job hours are multiplied so the whole menu uses the firm's hours at its going volume (job trades: `ProjectModel.hoursPerWeek`; handy and security: full-time people x 36). Labour per job then matches what the books pay.
- Backlog: job trades read the real order book (`fm.jobs` remaining hours / hours per week); handy and security show demand above capacity. A call-out starts at its lead time, a scheduled job at max(lead, backlog).
- Nothing here moves cash; callbacks and phases are shown, not paid again (the project model already runs milestones, retention, overruns and defects).

## Save keys
None new. `itemsv2` records (model, cost, prep, lead, capacity, stock, plans `order:<n>`) for the six trades only; `items27` list replaced only when untouched.

## Hooks the lead adds (shared files)
1. `Businesses/WaveHooks.swift` `weekly`, after `Wave6.weekly`: `Wave7.weekly(&s, i, data: data)`.
2. `Features/Companies/WaveItemBlocks.swift`: `Wave7ItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)`.
3. `pay_plans.json` `extraRoles` (optional, commission on what they sell): `"construction": ["pm"], "engcons": ["pm"]`, `"electrician": ["elec"], "plumber": ["plumb"], "handy": ["handy"]` (estimators and tradespeople who quote and close jobs), security stays hourly.
4. `itemcatalog.json` is single-line shared data: the add-item catalogue of the six trades is `extra` in `wave7_jobs.json`; the existing titles there (e.g. "Emergency call-out", "Heat pump install") match the extra names where they overlap, the rest need no edit.
5. `tables.json` EQ_KINDS: all six trades have the right kinds already (tools, lift, cam, scaf as `tool`; software `soft`; workstations `it`; radios, alarm centre `mach`). Missing and harmless: construction `exc`, `vans`, `crane` (vehicles, not kinds).

## Tests (Wave7Tests)
Registry, specs consistent with the books (calibration printed), install gives the real menu with neutral books and a table of price, materials, labour, profit, capacity per item, models and quote breakdown with live profit, construction phases, security contract hours, handy kit stock cycle, weekly labour refresh, touched list kept, not-opted-in no-op, record round trip, and `LEDGER_WAVE7=1` two-year probe before/after.
