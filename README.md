# Ledger

A business-management simulation for iPhone and iPad: double-entry books, countries with their own tax and labour rules, companies, groups, hiring, banking and online play.

- `native/`: the Swift engine (`Engine`) and the SwiftUI app (`App`). See `native/README.md`.
- `supabase/`: database migrations, SQL tests and the invite edge function for the online side.
- `apps.json`: the AltStore source, filled in by CI after each green app build.
- `MISSING.md`: what is still to do.
