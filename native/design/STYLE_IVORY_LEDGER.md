# Style: Ivory Ledger

Editorial private banking. A quiet dark page, flat sections divided by hairlines, serif for the figures that matter, champagne
only where something can be acted on. Flat by default; compact cards only where they truly help (see DESIGN_RULES revision 26 Oct).

## Rules
1. **Flat by default (no unnecessary containers).** Content sits on the page. Sections are separated by a 0.5 pt hairline and 14–18 pt of space, never by a filled box or a border.
2. **Three levels of type.** Serif (New York, `.serif`) for the hero figure of a screen and the screen title; Inter-like system sans for everything else; small caps (10.5 pt, semibold, +1.6 tracking, champagne) for section labels.
3. **Figures are tabular.** Every number uses monospaced digits and right-aligns in tables.
4. **Colour means something.** Champagne = label / link / the one action. Green = gain, red = loss, amber = warning. Nothing is coloured for decoration.
5. **Density without noise.** Key figures sit in a joined row with vertical hairlines (3 across). Tables have a small-caps header, one line per row, a sparkline for trend.
6. **Charts are small and honest.** Hairline grid, 1.4 pt line, a soft fill only under the main series, scale fitted to the data (never from zero for net worth).
7. **One primary action.** Next day is the only persistent filled champagne control (selected, destructive, disabled and urgent states have their own treatments), a pill bottom right with a 7-segment week progress at the left.
8. **Glass only floats.** The native tab bar and the Next day capsule may use the system material; nothing in the content does.

## Tokens
| Token | Value |
|-------|-------|
| page | `#111315` |
| text | `#EFE9DF` |
| muted | `#9D978E` |
| faint | `#6C6862` |
| hairline | `#EFE9DF` at 9 % |
| champagne | `#CFB185` |
| gain | `#86C79D` |
| loss | `#DC8770` |
| warning | `#D9AE62` |
| tab bar | `#0D0F11`, hairline on top |

Spacing: screen margin 22, section gap 16, row padding 9–10. Corners: 0 for content; capsule for the Next day pill and chips only.

## Screen recipes
- **Home**: date + country line, player name (serif 25), NET WORTH label with 1W/1M/1Y/ALL at the right, hero (serif 40), change line, chart, 4-up key figures, NEEDS YOUR ATTENTION (icon, company, text, chevron), COMPANIES (dot, name · trade, profit, cash), Next day pill.
- **Group**: title, VALUE OF HOLDINGS hero (serif 36) + 30-day change, allocation bar (flat segments), 3 × 2 key figures, revenue/profit chart, table Company | Value | Profit | revenue sparkline with health under the name.
- **Company**: back link, name (serif 26), trade · city · form · health, underline section tabs, PROFIT hero (serif 34) with margin and revenue growth at the right, key figures, chart, WHAT IS GOING ON with section links, LAST WEEK with thin bars and the bottleneck.
- **Lists and forms** (Bank, Settings, Invest, Staff…): rows with a hairline between, label left, value right, chevron when it opens; grouped by small-caps headers. Controls are text-weight, not filled.
