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
