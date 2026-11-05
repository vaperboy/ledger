import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Item page blocks for the project and job-contract model (construction, electrician, plumber, handyman, engineering office, security).
/// It draws nothing for an item that is not a real job of these trades.
struct JobItemBlocks: View {
    var engine: GameEngine
    var companyID: Int
    var itemID: String
    var currency: Currency

    var body: some View {
        if let f = JobContracts.facts(engine.state, companyID: companyID, itemID: itemID, data: engine.data) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if f.model == .stk { shelfBlock(f) } else {
                    quoteBlock(f)
                    crewBlock(f)
                    if !f.phases.isEmpty { phasesBlock(f) }
                    if f.warrantyRate > 0 { warrantyBlock(f) }
                }
                if f.isRecurring { recurringBlock(f) }
            }
        }
    }

    private func hoursText(_ h: Double) -> String { h < 10 ? String(format: "%.1f h", h) : String(format: "%.0f h", h) }

    private func daysText(_ d: Double) -> String {
        if d < 1 { return "same day" }
        if d < 14 { return String(format: "%.0f days", d) }
        return String(format: "%.0f weeks", d / 7)
    }

    private func quoteBlock(_ f: JobContracts.Facts) -> some View {
        let word: String = f.profit >= 0 ? "profit " : "loss "
        let perJob: String = word + itemAmount(abs(f.profit), currency) + " a job"
        let perHour: String = f.profitPerHour.map { (v: Double) -> String in (v >= 0 ? "profit " : "loss ") + itemAmount(abs(v), currency) + " an hour" } ?? ""
        let markup: String = String(format: "%.0f%% on materials", f.markup * 100)
        return TeamGroup("The quote") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Quoted price", value: itemAmount(f.price, currency), sub: f.note, rule: false)
                    FlatRow(label: "Materials at cost", value: itemAmount(f.materialsCost, currency), sub: f.markup > 0 ? "charged at " + itemAmount(f.materialsCharge, currency) + ", " + markup : "no markup")
                    FlatRow(label: "Left for labour", value: itemAmount(f.labourCharge, currency), sub: f.hours > 0 ? itemAmount(f.chargePerHour, currency) + " an hour charged" : "")
                    FlatRow(label: "Your people", value: itemAmount(f.labourCost, currency), sub: f.hours > 0 ? itemAmount(f.costPerHour, currency) + " an hour with employer cost" : "")
                    FlatRow(label: "Real cost with callbacks", value: itemAmount(f.fullCost, currency))
                    FlatRow(label: "Result", value: perJob, sub: perHour, tint: f.profit >= 0 ? Theme.gain : Theme.loss)
                }
            }
        }
    }

    private func crewBlock(_ f: JobContracts.Facts) -> some View {
        let kind: String = f.isCallout ? "Call-out: first in the queue" : "Scheduled job: waits in the backlog"
        let load: String = f.maxPerWeek > 0 ? String(format: "%.1f of %.1f a week", f.weeklyJobs, f.maxPerWeek) : String(format: "%.1f a week", f.weeklyJobs)
        let crew: String = "\(f.crewSize) " + (f.crewSize == 1 ? "person" : "people") + (f.needsVehicle ? " and a vehicle" : "")
        return TeamGroup("Crew, lead time and backlog") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Labour in the job", value: hoursText(f.hours), sub: f.jobWeeks >= 0.2 ? String(format: "about %.1f weeks on site", f.jobWeeks) : "", rule: false)
                    FlatRow(label: "Needs", value: crew)
                    FlatRow(label: "Type", value: kind)
                    FlatRow(label: "Lead time", value: daysText(Double(f.leadDays)), sub: "before the crew can start")
                    FlatRow(label: "Backlog ahead", value: String(format: "%.1f weeks", f.backlogWeeks), sub: "a new job starts in " + daysText(f.startInDays))
                    FlatRow(label: "Booked", value: load, sub: f.maxPerWeek > 0 ? String(format: "%.0f%% of the firm's hours", f.utilisation * 100) : "")
                    if !f.document.isEmpty { FlatRow(label: "Paperwork", value: f.document) }
                }
            }
        }
    }

    private func phasesBlock(_ f: JobContracts.Facts) -> some View {
        let sub: Double = f.phases.reduce(0.0) { $0 + $1.subcontract }
        return TeamGroup("Phases and subcontractors") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    ForEach(Array(f.phases.enumerated()), id: \.offset) { k, p in
                        FlatRow(label: p.name, value: itemAmount(p.amount, currency),
                                sub: (p.subcontract > 0 ? "subcontract " + itemAmount(p.subcontract, currency) + ", " : "") + String(format: "%.1f weeks", p.weeks), rule: k > 0)
                    }
                    FlatRow(label: "Subcontractors in all", value: itemAmount(sub, currency))
                    if f.retention > 0 { FlatRow(label: "Retention held back", value: itemAmount(f.retention, currency), sub: "paid after the defect period") }
                }
            }
        }
    }

    private func warrantyBlock(_ f: JobContracts.Facts) -> some View {
        let period: String = f.warrantyMonths > 0 ? "\(f.warrantyMonths) months" : "no fixed period"
        return TeamGroup("Warranty callbacks") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Warranty", value: period, rule: false)
                    FlatRow(label: "Jobs that come back", value: String(format: "%.1f%%", f.warrantyRate * 100))
                    FlatRow(label: "Callbacks a week", value: String(format: "%.2f", f.callbacksPerWeek))
                    FlatRow(label: "Cost of callbacks", value: itemAmount(f.callbackCostPerWeek, currency), sub: "a week", tint: Theme.loss)
                }
            }
        }
    }

    private func recurringBlock(_ f: JobContracts.Facts) -> some View {
        let per: String = f.periodWeeks == 52 ? "a year" : (f.periodWeeks == 26 ? "every 6 months" : "every \(f.periodWeeks) weeks")
        let title: String = f.isContract ? "Contracts and rota" : "Plan members"
        return TeamGroup(title) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: f.isContract ? "Sites or clients on contract" : "Members", value: String(format: "%.0f", f.members), rule: false)
                    FlatRow(label: "Billed each", value: itemAmount(f.visitsPerPeriod * f.price, currency), sub: per)
                    FlatRow(label: "Billed in all", value: itemAmount(f.recurringPerPeriod, currency), sub: per)
                    FlatRow(label: "Leaving", value: String(format: "%.1f", f.leavingPerPeriod), sub: String(format: "%.0f%% ", f.churnPerPeriod * 100) + per)
                    if f.isContract {
                        FlatRow(label: "Crew hours to cover", value: String(format: "%.0f a week", f.crewHoursPerWeek), sub: String(format: "%.1f full-time people", f.crewFTE))
                    }
                }
            }
        }
    }

    private func shelfBlock(_ f: JobContracts.Facts) -> some View {
        let cover: String = f.weeksOfCover.map { (v: Double) -> String in String(format: "%.1f weeks", v) } ?? "no sales yet"
        return TeamGroup("On the shelf") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "In stock", value: "\(f.stock)", sub: f.onOrder > 0 ? "\(f.onOrder) on order" : "", rule: false)
                    FlatRow(label: "Cover", value: cover)
                    FlatRow(label: "Sold a week", value: String(format: "%.0f", f.weeklyJobs))
                    FlatRow(label: "Cost each", value: itemAmount(f.materialsCost, currency))
                }
            }
        }
    }
}
