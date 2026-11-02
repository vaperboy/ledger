# Release cleanup audit (Stage 9)

Nothing was deleted. Only `native/App/project.yml` (bucket 1) and `.gitignore` were touched.
Sizes are on-disk (`du -sk`, KB).

## Kept (proved used or required)
| Path | Size | Evidence |
|---|---|---|
| `native/App/Ledger/Resources/faces-sheet.jpg`, `faces-suits.jpg`, `art/workers-sheet.jpg`, `art/managers-sheet.jpg` | 1268+792+740+760 | `Design/FaceSheet.swift` `fileName()` loads all four by name |
| `Resources/art/cells/**` (6 MB) | 5872 | `Design/ArtLibrary.swift` reads `cells/<sheet>/manifest.json`; shipped via the `type: folder` source in project.yml |
| `Assets.xcassets` AppIcon, AccentColor, LaunchBackground, AppPhotos, Thumbs | 904 | project.yml settings; `ShopPhoto`/`TechProProduct`/`AirStayApp`/`AtlasApp`; `ThumbnailView` `UIImage(named:)` |
| `LedgerTests`, `LedgerUITests` | - | separate targets, not in the app bundle; tests are never removed |
| `native/Engine` (incl. `Tests/**/Golden/*.json`) | 8.8 MB | engine package and its tests; Engine `Resources` read by the engine |
| `native/tools`, `native/docs`, licences | 236 K / 1.3 MB | referenced by docs and CI; purpose clear |

## Bucket 1: EXCLUDE from the release build (applied in project.yml)
| Path | Size | Evidence | Recommendation |
|---|---|---|---|
| `Resources/art/cars-sheet.jpg` | 436 | no Swift/JSON reads the file; only cells (`ArtLibrary`) are read; comment mention only | excluded (applied) |
| `Resources/art/logos-sheet.jpg` | 784 | same | excluded (applied) |
| `Resources/art/luxury-sheet.jpg` | 804 | same | excluded (applied) |
| `Resources/art/premises-sheet.jpg` | 908 | same | excluded (applied) |
| `Resources/art/trophies-sheet.jpg` | 648 | same | excluded (applied) |
| `Resources/art/cells/**` from the generic source | - | re-added once as a folder resource (avoids a duplicate flat copy) | excluded (applied) |

Total excluded from the IPA: 3580 KB. The five sheets stay in the repo (originals for `native/tools/slice_sheets.py`).

## Bucket 2: REMOVE from build resources (listed, not applied)
| Path | Size | Evidence | Recommendation |
|---|---|---|---|
| `native/App/Ledger/Assets.xcassets/Thumbs/README.md` | 16 | documentation inside the asset catalogue; referenced only by a comment in `ThumbnailView.swift`; Xcode does not compile it | move to `native/docs` (keep content); then it no longer sits in the catalogue |

Count 1, 16 KB. Empty `Thumbs/{luxury,person,premises,trade}/Contents.json` are tiny, are the catalogue structure `ThumbnailView` expects: keep.

## Bucket 3: DELETE permanently (owner approval required, never applied)
| Path | Size | Evidence | Recommendation |
|---|---|---|---|
| `native/design/mockups/A_dashboard.png` | 1672 | no reference in any doc, code, or script (grep of file name) | early mockup, likely superseded by `mockups/master`; owner to confirm, then delete |
| `native/design/mockups/C_company.png` | 1584 | same | same |
| `native/design/mockups/B_group.png` | 1568 | same | same |
| `.github/workflows/yesmain.yml` | 4 | near-duplicate of `main.yml` (same name, differs by a few lines), now `workflow_dispatch` only; legacy web game | owner to confirm legacy web build is retired |

Count 4, 4828 KB. Everything else under `native/design` (22 MB, outside the app target, not shipped; referenced by DECISIONS/HANDOFF) is kept.

## Other findings
- Not shipped in the IPA: `native/design`, `native/docs`, `native/tools`, `native/Engine/Tests`, `.github`, golden JSON, `RELEASE_NOTES.md`, `apps.json` (all outside `native/App/Ledger`).
- No build artefacts, caches, `.DS_Store`, `.pyc`, `.ipa` or `.xcodeproj` are tracked. `.gitignore` now also covers generated `native/App/*.xcodeproj/`, `*.ipa`, `*.xcarchive`, `*.dSYM/`.
- No `.claude/` folder is tracked.
- Workflows: `main.yml` and `yesmain.yml` already manual-only. `native-ios.yml` (CI), `native-ipa.yml`, `native-testflight.yml` kept.

## Verification checklist for the release package
- [x] `python3 -c "import yaml;yaml.safe_load(open('native/App/project.yml'))"` passes
- [ ] `xcodegen generate` then app-build green on CI; engine-tests green
- [ ] Unzip the IPA: `Payload/Ledger.app` contains no `*-sheet.jpg` except `workers-sheet.jpg`, `managers-sheet.jpg` (and `faces-sheet.jpg`, `faces-suits.jpg`)
- [x] `art/cells/<sheet>/manifest.json` present for cars, logos, luxury, premises, trophies
- [ ] No `LedgerTests`/`LedgerUITests`, `.md`, `.py`, golden `.json`, or mockup files inside the bundle (source check: only Thumbs/README.md is in the sources, owner call pending)
- [ ] Bundle size dropped by about 3.5 MB versus the previous build
- [ ] Launch on simulator: faces (all four sheets), car/logo/luxury/premises/trophy art, AirStay/TechPro photos, thumbnails and app icon all render
- [ ] Unit and UI tests still pass after any approved deletions
