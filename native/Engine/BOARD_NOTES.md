# Boards: structure and authority

Audit of the engine against the board arrangement rules. "Now" is the behaviour after the changes in this commit; the gap column says what was missing before, or what is still open.

| Row | Behaviour | Gap |
|---|---|---|
| Standalone company = own board | Board key `co:<id>`; a board binds (`boardActive`) once an outside holder exists, otherwise it is advisory. | None. |
| One company, several branches = one shared board | `boardParent` resolves `branch.of` (up to 4 hops) when the parent is live, set up, same country and same holding; the branch uses the parent's key and is listed in `boardCompanies`, not in `boardKeys`. Chains (`chain`) were already one board per chain. | Before: every `branch.of` company got its own `co:` board. Open: outside owners vote only on their own company's matters (a branch's co-owners are not the parent's). |
| Separate subsidiaries = one board each | Subsidiaries under a holding keep `co:<id>`; the holding votes through its stake (`HoldingStakes`, `seat`, `votingPercent`). A branch under a different holding or country keeps its own board. | None. |
| Holding = own parent board | A holding is never merged into a subsidiary board (`boardKey` is `co:<holdingID>`); stakes give it a seat or control on each subsidiary board. | Open: `boardKeys` still skips `hold`, so a holding has no scheduled meetings or agenda, only seats you add explicitly. |
| Franchise location | Player as franchisee: the unit is your own company with its own board; the franchisor holds contract rights only and has no seat. Player as franchisor: units are records in `fr.units`, owned by the franchisee, with no board on your side. | Open: nothing models a franchise unit that you own inside your own franchise system as a branch; if it is created with `branch.of` it joins the parent board. |
| Store or branch manager is not a director | Managers attend (`voters`, `Counterpart`) but vote only if explicitly seated. | Before: the CEO and regional managers were `votes: true` in `voters`, and chain executives were written into the board as role-less `exec` seats that were invisible yet consumed capacity. Both removed; `heldSeatCount` ignores legacy role-less entries. |
| Layer 1: owners appoint the board, vote reserved matters | Directors are elected by share vote (`fillSeat`), outside owners with 20% or more take a director seat (`ownersWeek`), removal is a share vote (`seatRemovalTerms`); sale, close and loan use `boardVote`. | None. |
| Layer 2: board approves big moves, appoints and dismisses the CEO | Sale, close, loan: share vote. CEO dismissal: share vote, the owner alone with a majority. | Before: with an outside owner seated as director, a majority owner dismissed the CEO alone. Now `ceoDirectors` applies (see below). |
| Layer 3: CEO and management run operations | Manager, team heads, regionals hire and run daily work (`ManagerTeam`, `ManagerPromotions`, `AutoHire`). | None. |

## Changes

- `ManagerModel.boardParent(_:_:)`, `boardKey`, `boardKeys`, `boardCompanies`: branches share the parent board.
- `ManagerModel.voters`: CEO, regional and store managers no longer vote.
- `hireExecutive` and `applyPromotion` no longer write `exec` seats.
- `ManagerModel.ceoDirectors(_:companyID:appointing:)`: when you hold more than half of the votes and an outside owner has a director seat, you and each director get one vote on dismissing the CEO (`proposeCEOChange`, `boardVote(kind: "ceo")`) and on appointing one (`hireTeam` key `ceo`); more than half passes, a tie fails. `releaseTeam` key `ceo` follows the same vote. When outsiders hold control, or no outsider has a seat, the share vote applies as before.
- `BoardVote` has `directorsDecide`, `directorsYes`, `directorsTotal`, `directors`.

## Not changed

- Hiring and firing the store manager (`managerID`, `ManagerModel.fire`) stays operational: the owner decides.
- A holding's own seats vote with you but are not counted as directors in `ceoDirectors`.
