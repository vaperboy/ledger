# Saves

## Native save (`*.ledgersave`)

A JSON file:

```json
{ "format": "ledger-native", "version": 1, "savedAt": "2026-10-19T10:00:00Z",
  "summary": { "playerName": "…", "countryCode": "UK", "week": 26, "netWorth": 123456, "companies": 2, "savedAt": "…" },
  "state": { …the game state… } }
```

* `format` must be `ledger-native`. A file of another kind is refused.
* `version` is the version of this envelope. `NativeMigrations.upgrade` brings an older file up one version at a time; a file from a
  **newer** app than this one is refused with a clear error and never overwritten.
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

Add the accessor on the record type (for example in `GameCore/State/Company.swift`), give it a default for old saves, and — only if
the old value must be changed — add a step to `NativeMigrations.steps`.

The last-50-actions pass (`AccountSupply`, `RivalAbsorb`, `OfficeChecks`) saves in the original's own names, so legacy saves and native saves are the same shape and need no migration: `rest["l39"]` (links to business customers), `flags.match27`, `flags.brand27`, `branch.of` and `branch.r` on a company, `uc27.resp` on a rival, `lastRev` on a company.

Open negotiations (stage 2): a talk that is still open is kept under the key `neg` on the record it concerns, and the key exists only while a talk is open: `{p: party (the employer), n: offers answered, o: last offer, c: standing counter, w: week}`. It is on a candidate (`npcs`), on a rival owner (`mk.<key>.riv[]`), on a sale offer and in the data of a pay-raise message. A candidate who lost patience and took another job has `hired: -9`. Saves without the key load as before.

Supplier terms (stage 3, `SupplyTerms` / `SupplyDeals`) add keys that exist only while they are set, so older saves load and write back unchanged: `rest["sinv"]` (open supplier invoices: id, buyer, provider company or vendor id, face amount `f`, amount `a` with late interest, issued `w0`, due `d`, weeks late `l`), `pterm.goods` on a company (agreed goods payment terms), `lt` (weeks of recent late invoices), `supCutI` and `supCutB` (supplier cut-off from invoices and from monthly bills; `supCut` stays the one value stock buying reads), `sdl` (negotiated price per scope and the cool-off after a walk-out), `neg` on a company (a price talk still open), `payables.inv` (what the company owes on invoices), `tm` on a link in `rest["l27"]` (own-company payment terms), `ic` / `ac` / `ld` on a receivable (an invoice to one of your companies; a business customer's invoice and the weeks it will be late), `lc` / `lw` on a key account (late payment record), and `rules.sup[input]` on a chain (the chain-wide supplier rule).
