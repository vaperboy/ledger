import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Wave 6 item page blocks (appointment and crew model: barber, driving school, physio, dental, car cleaning, cleaning company).
/// Hook for `ItemPageView.body`, after `supplyBlock(pg, cur)`: `Wave6ItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)`.
/// It draws nothing for an item that is not a real service of the wave.
struct Wave6ItemBlocks: View {
    var engine: GameEngine
    var companyID: Int
    var itemID: String
    var currency: Currency

    var body: some View {
        if let f = Wave6.facts(engine.state, companyID: companyID, itemID: itemID, data: engine.data) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if f.model == .stk { shelfBlock(f) } else { jobBlock(f) }
                if f.model != .stk { noShowBlock(f) }
                if f.isRecurring { recurringBlock(f) }
            }
        }
    }

    private func minutesText(_ m: Int) -> String {
        if m >= 120 && m % 60 == 0 { return "\(m / 60) hours" }
        return "\(m) min"
    }

    private func jobBlock(_ f: Wave6.Facts) -> some View {
        let perHour: String = f.profitPerResourceHour.map { (v: Double) -> String in (v >= 0 ? "profit " : "loss ") + itemAmount(v, currency) + " an hour" } ?? "not available"
        let load: String = f.maxPerWeek > 0 ? String(format: "%.0f of %.0f a week", f.weeklyUnits, f.maxPerWeek) : String(format: "%.0f a week", f.weeklyUnits)
        return TeamGroup("The job") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Takes", value: minutesText(f.minutes), sub: f.seats > 1 ? "up to \(f.seats) customers at once" : "", rule: false)
                    FlatRow(label: "Needs", value: f.skill, sub: f.resource)
                    if f.pack > 1 { FlatRow(label: "Sold as", value: "a block of \(f.pack)", sub: "priced per job, paid in advance") }
                    if f.travelMinutes > 0 { FlatRow(label: "Travel each job", value: "\(f.travelMinutes) min") }
                    FlatRow(label: "Materials and direct cost", value: itemAmount(f.unitCost, currency), sub: "each job")
                    FlatRow(label: "Return on the room, chair or crew", value: perHour, tint: (f.profitPerResourceHour ?? 0) >= 0 ? Theme.gain : Theme.loss)
                    FlatRow(label: "Booked", value: load, sub: f.maxPerWeek > 0 ? String(format: "%.0f%% of the time", f.utilisation * 100) : "")
                }
            }
        }
    }

    private func noShowBlock(_ f: Wave6.Facts) -> some View {
        let rate: String = String(format: "%.1f%%", f.noShowRate * 100)
        let lost: String = itemAmount(f.lostRevenuePerWeek, currency) + " a week"
        let remind: String = f.remindersOn ? "Reminders are on" : "No reminder system"
        return TeamGroup("No-shows and rebooking") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "No-shows", value: rate, sub: remind, rule: false)
                    FlatRow(label: "Missed a week", value: String(format: "%.1f", f.noShowsPerWeek))
                    FlatRow(label: "Rebook", value: String(format: "%.0f%%", f.rebookRate * 100), sub: "of those who missed")
                    FlatRow(label: "Lost for good", value: lost, tint: Theme.loss)
                }
            }
        }
    }

    private func recurringBlock(_ f: Wave6.Facts) -> some View {
        let per: String = f.periodWeeks == 52 ? "a year" : (f.periodWeeks == 26 ? "every 6 months" : "every \(f.periodWeeks) weeks")
        let title: String = f.isContract ? "Contracts and rota" : "Members"
        return TeamGroup(title) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: f.isContract ? "Sites or homes on contract" : "Members", value: String(format: "%.0f", f.members), rule: false)
                    FlatRow(label: "Visits each", value: String(format: "%.0f", f.visitsPerPeriod), sub: per)
                    FlatRow(label: "Billed", value: itemAmount(f.recurringPerPeriod, currency), sub: per)
                    FlatRow(label: "Leaving", value: String(format: "%.1f", f.leavingPerPeriod), sub: String(format: "%.0f%% ", f.churnPerPeriod * 100) + per)
                    if f.isContract {
                        FlatRow(label: "Crew hours to cover", value: String(format: "%.0f a week", f.contractHoursPerWeek), sub: String(format: "%.1f full-time people", f.crewFTE))
                    }
                }
            }
        }
    }

    private func shelfBlock(_ f: Wave6.Facts) -> some View {
        let cover: String = f.weeksOfCover.map { (v: Double) -> String in String(format: "%.1f weeks", v) } ?? "no sales yet"
        return TeamGroup("On the shelf") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "In stock", value: "\(f.stock)", sub: f.onOrder > 0 ? "\(f.onOrder) on order" : "", rule: false)
                    FlatRow(label: "Cover", value: cover)
                    FlatRow(label: "Sold a week", value: String(format: "%.0f", f.weeklyUnits))
                    FlatRow(label: "Cost each", value: itemAmount(f.unitCost, currency))
                }
            }
        }
    }
}
