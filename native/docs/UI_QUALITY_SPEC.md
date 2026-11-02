# UI quality spec (owner brief, 2 Nov 2026, binding for all screens)
Goal: one coherent premium native iOS feel. Shared rules and reusable components first; no rewrite, no removed functionality, no changed business logic or save format.

## Navigation
- Main tabs slide horizontally (200-300 ms, spring, no cross-fade). Each tab keeps its own history; tapping a tab opens its ROOT (never an old submenu); tapping the active tab returns to root. Subpages slide forward, back reverses.
- During a swipe, inactive pages get no taps (hit testing off); no duplicate navigation; vertical scroll beats horizontal swipe; interrupted gestures leave state consistent. Tab bar stays still.

## Screen types (every screen is exactly one)
A fixed (no scroll either way), B vertical scroll only when content overflows (bounded, no blank space, no sideways), C intentional horizontal navigation, D contained scrolling area inside a fixed screen or popup. Background never scrolls under a popup. No nested competing scroll views. Small iPhones: compact the content instead of letting fixed screens overflow.

## Popups
Contextual popover (small, near the control), standard modal (sized to content, dimmed background, locked background, consistent close), confirmation (consequences first, destructive clearly marked, never confirmed by a background tap), full-screen workflow only when really needed. Owner decision kept: popups open centred in the report style, not from the bottom. Long content scrolls inside the popup only. Never an empty or oversized popup; content must always be visible.

## Sliders and switches
One slim modern slider (thin track, refined thumb, big invisible touch area, value shown, snapping where useful, haptic only at meaningful points); important financial sliders show the consequence live (weekly cost, new percentage and cost, payment and remaining balance). Smaller refined switches.

## Reports
Report entrance controlled; title and period first; figures count up (revenue up, expenses up, profit/loss clear), charts draw, gains green / losses red / warnings amber / milestones champagne; real simulation values only; never force waiting; skip/continue always available.

## Animation timing
Button 100-160 ms; tabs and subpages 200-300; modal 220-350; numbers 250-450; charts 500-900; milestone 700-1200; acquisition 1000-1600. Smooth, little bounce, haptics sparse, Reduce Motion respected.

## Compact layout
Information-dense lists with dividers instead of a card per setting; no truncated names; no shrinking text below readable size; touch targets stay comfortable.
