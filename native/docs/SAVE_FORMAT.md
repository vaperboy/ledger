# Saves

## Native save (`*.ledgersave`)

A JSON file:

```json
{ "format": "ledger-native", "version": 1, "savedAt": "2026-10-19T10:00:00Z",
  "summary": { "playerName": "…", "countryCode": "UK", "week": 26, "netWorth": 123456, "companies": 2, "savedAt": "…" },
  "state": { …the game state… } }
```

* `format` must be `ledger-native`. A file of another kind is refused.
* `version` is the version of this envelope. `NativeSaveFormat.check` reads only the current version: a file from a
  **newer** app is refused with a clear error and never overwritten, an older one is unreadable (nothing is published yet, so there are no old saves to carry over).
* `state` is the game state. Its keys keep the names the original game used (`cos`, `loans`, `inbox`, `rs`, …) so that an import is lossless and
  so that fields the native code has not ported yet survive a round trip.
* Native-only additions live under their own keys and are optional: `dayHist` (daily history for the Home charts).

## Where files go

`Application Support/Ledger/Saves/`

| File | What |
|---|---|
| `current.ledgersave` | the running game, written after every action and day |
| `current.previous.ledgersave` | the save before the last one; used automatically if `current` cannot be read |
| `Backups/backup-weekN.ledgersave` | written every fourth week; the last six are kept |
| `Imports/original-<time>.txt` | the exact text of a save imported from the web game, never changed or deleted |

Writing is safe against crashes and full disks: the new save is written to a temporary file, read back and checked, and only then
swapped in with `rename`, which replaces the file in one step.

## Importing from the HTML game

`LegacyImporter.importText` accepts what the original produced: plain JSON, `LZ1:` (15-bit lz-string) or `LZ64:` (6-bit lz-string)
text, save version 3 to 5. Version 3 saves get the pay basis and last-raise fields the later versions need. The native game is
always played day by day, so `dmode` is set. Saves from a newer game than version 5 are refused.

The importer is tested with real saves made by the original (`Golden/save_*.json`) and with the compression round trip (`lz_pack`).
What is carried but **not simulated yet**: companies of trades not ported (they keep their data), startups, private equity,
luxury, football clubs.

## Adding a field

Add the accessor on the record type (for example in `GameCore/State/Company.swift`), give it a default, and raise `NativeSaveFormat.currentVersion` only when the envelope itself changes.

The last-50-actions pass (`AccountSupply`, `RivalAbsorb`, `OfficeChecks`) saves in the original's own names, so legacy saves and native saves are the same shape and need no migration: `rest["l39"]` (links to business customers), `flags.match27`, `flags.brand27`, `branch.of` and `branch.r` on a company, `uc27.resp` on a rival, `lastRev` on a company.

Open negotiations (stage 2): a talk that is still open is kept under the key `neg` on the record it concerns, and the key exists only while a talk is open: `{p: party (the employer), n: offers answered, o: last offer, c: standing counter, w: week}`. It is on a candidate (`npcs`), on a rival owner (`mk.<key>.riv[]`), on a sale offer and in the data of a pay-raise message. A candidate who lost patience and took another job has `hired: -9`. Saves without the key load as before.

Supplier terms (stage 3, `SupplyTerms` / `SupplyDeals`) add keys that exist only while they are set, so older saves load and write back unchanged: `rest["sinv"]` (open supplier invoices: id, buyer, provider company or vendor id, face amount `f`, amount `a` with late interest, issued `w0`, due `d`, weeks late `l`), `pterm.goods` on a company (agreed goods payment terms), `lt` (weeks of recent late invoices), `supCutI` and `supCutB` (supplier cut-off from invoices and from monthly bills; `supCut` stays the one value stock buying reads), `sdl` (negotiated price per scope and the cool-off after a walk-out), `neg` on a company (a price talk still open), `payables.inv` (what the company owes on invoices), `tm` on a link in `rest["l27"]` (own-company payment terms), `ic` / `ac` / `ld` on a receivable (an invoice to one of your companies; a business customer's invoice and the weeks it will be late), `lc` / `lw` on a key account (late payment record), and `rules.sup[input]` on a chain (the chain-wide supplier rule).

Fix/open-engine keys, all written only when set: a project job `due` (planned finish week, jobs taken on after this change), a fixed-term staff record `fts` (start of the run of terms) and `ftr` (renewals, only after the first). Old saves have none of them and load unchanged.

Stage 2 (financial systems), all keys written only when set, no resets, older saves load unchanged:
* Company: `led` (transaction ledger: `"w<week>"` -> rows `[amount, count, category, label, ref, lastDay]`, last 104 weeks), `ledFrom` (week the ledger began), `lednotes` (notes by row id), `invb` and `invN` (customer invoice book and counter), `prun` and `prunN` (payroll run records), `acx` (named Accounting users -> level), `legal` (form, since, name, shares, conversion history), `convMonthProfit` (present only between a conversion and the next month close).
* Receivable: `iv` (the invoice number it belongs to). Company: `sinvPaid` (paid supplier invoices). Staff record: `hrsAct` (hours worked by month: [hours, overtime, weeks]). Invoice book rows have `st` draft/sent/paid/bad and `sw` (week sent). Payroll run rows have `fee` and per-line `itx`/`esoc` (withholding). Cost category `fin` in `bk` (loan arrangement fees).
* Loan: `ptm` (calendar month the instalment was last settled), `app` (application record: week, fee, net, account), `guarReleased`, `guarLock`, and the open bank talk under `neg`.
* Personal tax: `enkFrozen` (already existed, now written at conversion; cleared with the tax year).
* `pr29.mode` (old payroll choice) is kept but no longer used.

Stage 3 employment (engine), all keys written only when set; older saves load and write back unchanged, and nothing is migrated (the working percentage is derived from the existing `hrs`/`pt`, so an old 20-hour part-timer reads as 53.3 percent and a 25-hour seasonal worker as 66.7 percent):
* Staff record: `chist` (contract history, last 40: `{w, k, t}`), `wlog` (work log, last 26 weeks, one number row per week: week, contracted and worked hours x4, tasks assigned and done, mistakes, late, sick week, initiative, guidance, informed, silent, complaints), `crsN` (courses taken), `uw` (running discontent), `dis` (week disengagement began), `voiced`, `silentW`, `broke` (week a promise was broken), `bp`/`ex` as before (now also set at hire), `ft`/`ftl`/`fts` now also for any temporary length and for a seasonal contract that ends with its season.
* Person record: `prm` (promises, last 12: id, company, kind, text, detail, made, due, status, baseline, resolved week, renegotiations), `xp` (hire expectations), `trialObs` (trial week observations), `tf` (transient, exists only inside a hire call), `neg` may now also hold `a` (the candidate has opened with an ask) and `t` (fingerprint of the terms the figures belong to).
* Company record: `ptr` ({k: weeks promises were kept, b: weeks they were broken}, last 8 each).
* `trialRes` (old trial skill) is no longer written; old values stay in the save, unread.

Phone apps AirStay, TechPro Store and Atlas Insurance (1 Nov 2026 night), all keys written only when set; older saves load unchanged:
* Company: `ord` (TechPro Store orders placed by this store company, newest first, last 40: number `no`, placed week/day `w`/`d`, delivery method `del`, carrier text `car`, goods `goods`, shipping `ship`, paid at checkout `paid`, receipt company `rc`, last arrival as an absolute day `eta` (week x 7 + day), status `st` transit/done, `lines` with `k` kind, `eq`, `nm`, `q`, `i` offer index, `v` vehicle offer id, `pl` plan, `pay`, `g` goods, `c` charged, per-line `eta` and `done`, `u` the used listing as shown), `rcpt` (receipts filed with this company's Accounting records, newest first, last 200: `no`, `k` order/lease/policy, `t`, `d`, `a`, `w`/`dy`, `p` payer), `polNo` (policy number and start week/day per insurance product that is on).
* Company `prem` (the place it works in) may now also hold `ref` (the AirStay reference) and `rc` (the company whose Accounting holds the receipt).
Stage 4 (startups, investment, business creation), all keys written only when set; older saves load unchanged:
* Company: `cap` = { total (shares in issue), me (your shares) } and each `holders[]` entry gains `sh` (its shares). `pct` and `ownership` stay as derived caches. An older save with only percentages is migrated on the first week: counts of 1,000,000 shares are built from the percentages (you keep the ownership you were shown; if holders plus you came to more than 100 the holders are scaled back, if less the gap becomes a holder named "Other shareholders"). Nothing is lost, the total never exceeds 100.
* Company `flags.stockShare` (0, 0.5 or 1): the share of the standard opening stock the owner chose; absent means 1 (older companies). `flags.integ`, `integCost`, `integPeople`, `integKit`: a bought rival's integration (week, cost, people and equipment moved).
* New hidden trade `startup` (in `trades`, not in `order`): a founded startup is a Company of this type. `rest["founded"][n]` keeps the product record (`sw16`: cat, prod, model, selfH, prog, phase build / beta / ready / live, cust, revW, int, use, deals, price) and gains `cid` (the company id, equal to `id`), `q0`, `wantTeam`, `hiredTeam`. The old blob keys `cash`, `burn`, `val` (now refreshed weekly), `pct` are no longer the source of truth; the company is. Older startup blobs without `cid` are read as ended.
