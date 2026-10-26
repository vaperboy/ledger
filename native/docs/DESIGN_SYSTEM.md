# Design system: old money meets private fintech

| Token | Use | Value |
|---|---|---|
| `Theme.walnut` / `walnutRaised` | background, raised surface | very dark brown |
| `Theme.leather`, `Theme.glass` | cards: charcoal leather under smoked glass | warm charcoal, translucent |
| `Theme.ivory`, `ivoryMuted`, `ivoryFaint` | text | warm ivory in three strengths |
| `Theme.gold`, `goldDeep` | champagne gold: primary action, selected, sparklines | `#E6CF9A` → `#C1A360` |
| `Theme.roseGold` | accent: debt bar, secondary actions | `#C99A8B` |
| `Theme.gain` / `loss` / `caution` | green, red, amber — only for meaning, never decoration | muted |

Type: serif with tabular digits for every money figure (`Font.figure`), small tracked capitals for labels (`SectionLabel`), the system
text style for body so Dynamic Type works.

Components: `Card`, `GoldButtonStyle` (one per screen, the main action), `QuietButtonStyle`, `DeltaPill` (arrow, amount and a percent
only when it is meaningful), `Sparkline` (real history, empty line when there is none), `MiniBars`, `Chip`, `Meter`, `AmountField`
(types in the displayed currency, converts to the game's unit), `SectionTabs`.

Rules for numbers on screen: a figure and the text that explains it come from the same value (the net worth card shows assets, debts and
net from one `NetWorth`); percentages are hidden when the base is too small to mean anything; daily and weekly changes are green up /
red down with an arrow, so colour is never the only signal.

Motion: restrained. Cards expand with `.snappy`, the next-day bar fills seven segments, nothing bounces. Haptics (`Haptics`): a soft tap
when a day passes, a medium one when a week completes, a selection tick when switching a section, success / warning / error for
results. All can be turned off in Settings.

iPad: the tab bar becomes a sidebar (`NavigationSplitView`), Home uses two columns, content is capped at a readable width.

## Navigation menus never scroll sideways
- `SectionTabs` is the one switcher: up to 5 items in an equal-width row (44 pt tall, text scales down, never clips); more than 5 shows a fixed row of `primary` (default first 4) plus a "More" menu. Selected fixed item: accent underline; in the menu: checkmark, and the "More" cell turns accent and shows the chosen title. Badge counts of hidden items roll up onto "More".
- Company sections: fixed Overview, Team, Finances, Operations; everything else (Marketing, Customers, Market, Setup, family sections) sits under More.
- No horizontal `ScrollView` for navigation, filters or option chips: use `SectionTabs`, or `WrapRow` (wrapping chips) for action/option buttons.
