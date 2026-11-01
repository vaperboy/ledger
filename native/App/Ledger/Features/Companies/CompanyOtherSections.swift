import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Customer complaints, placed at the end of Operations: a mailbag (a quote and three ways to answer, each with what it costs).
/// Development moved to Sales (`CompanyDevelopment`), named for the trade; giving up premises and changing the accountant moved to
/// Workplace and Insurance and advisers.
struct CompanyOtherSections: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    /// One open complaint, wrapped so a list of them is Identifiable.
    private struct Complaint: Identifiable {
        var id: Int
        var who: String
        var text: String
        var raw: JSONValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            complaints
        }
    }

    // MARK: Complaints, a mailbag

    private var complaintItems: [Complaint] {
        engine.openComplaints(companyID: company.id).map { Complaint(id: $0["id"].int, who: $0["who"].string, text: $0["t"].string, raw: $0) }
    }

    @ViewBuilder private var complaints: some View {
        let open: [Complaint] = complaintItems
        if !open.isEmpty {
            TeamGroup(title: "Complaints", trailing: {
                HStack(spacing: 6) {
                    RedBubble(count: open.count, size: .small)
                    Text("answer within two weeks").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }) {
                ForEach(open) { c in complaintCard(c) }
            }
        }
    }

    private func complaintCard(_ c: Complaint) -> some View {
        Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TeamInitials(name: c.who, size: 34)
                    Text(c.who).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Spacer(minLength: 0)
                }
                Text("\u{201C}\(c.text)\u{201D}").font(.serifTitle(15)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                CardLine()
                HStack(alignment: .top, spacing: 8) {
                    answerTile(c, .refund, glyph: Glyph.cost, title: "Refund", note: "Costs money, settles it", tint: Theme.gold)
                    answerTile(c, .sorry, glyph: Glyph.person, title: "Apologise", note: "Free, may not be enough", tint: Theme.gold)
                    answerTile(c, .ignore, glyph: Glyph.warning, title: "Ignore", note: "Risks a bad review", tint: Theme.caution)
                }
            }
        }
    }

    private func answerTile(_ c: Complaint, _ a: Satisfaction.Answer, glyph: String, title: String, note: String, tint: Color) -> some View {
        Button {
            Haptics.tap()
            answer(c.raw, a)
        } label: {
            VStack(spacing: 5) {
                GlyphView(glyph: glyph, size: 18, weight: 1.6, tint: tint)
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivory)
                Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(tint.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(title). \(note)")
    }

    private func answer(_ c: JSONValue, _ a: Satisfaction.Answer) {
        let r = store.act { $0.answerComplaint(companyID: company.id, complaintID: c["id"].int, answer: a) }
        switch (a, r ?? nil) {
        case (.refund, _): store.show("Refunded. The customer is satisfied.", tone: "good")
        case (.sorry, true?): store.show("They accepted the apology.", tone: "good")
        case (.sorry, _): store.show("They are still unhappy.", tone: "warn")
        default: store.show("Ignored. Expect a bad review.", tone: "warn")
        }
    }
}

/// Places in a chain that are short of a role, with a sister store that has one to spare: each a small transfer card,
/// the store that needs a worker on one side and the one with a spare on the other.
struct ChainStaffShortages: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var chainID: Int

    private struct Gap: Identifiable {
        var id: String
        var storeID: Int
        var role: String
        var spareAt: Int?
    }

    private var gaps: [Gap] {
        engine.staffShortages(chainID: chainID).map { Gap(id: "\($0.storeID)-\($0.role)", storeID: $0.storeID, role: $0.role, spareAt: $0.spareAtStoreID) }
    }

    var body: some View {
        let list: [Gap] = gaps
        if !list.isEmpty {
            TeamGroup(title: "Short of staff", trailing: {
                Text(list.count == 1 ? "1 place" : "\(list.count) places").font(.system(size: 11)).foregroundStyle(Theme.caution)
            }) {
                ForEach(list) { g in gapCard(g) }
            }
        }
    }

    private func storeName(_ id: Int) -> String { engine.state.company(id)?.name ?? "Store" }

    private func gapCard(_ g: Gap) -> some View {
        Card(padding: 12, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconCircle(glyph: Glyph.warning, size: 34, tint: Theme.caution)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(storeName(g.storeID)).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("Needs a \(g.role)").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
                    }
                    Spacer(minLength: 0)
                }
                if let from = g.spareAt {
                    CardLine()
                    HStack(spacing: 8) {
                        Text(storeName(from)).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                        GlyphView(glyph: Glyph.chevron, size: 11, weight: 2, tint: Theme.ivoryDim)
                        Text(storeName(g.storeID)).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                        Spacer(minLength: 8)
                        QuietButton(title: "Move one") { move(from: from, to: g.storeID, role: g.role) }
                    }
                    Text("Has one spare; the worker changes store.").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                } else {
                    Text("No sister store has one to spare. Hire for it.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func move(from: Int, to: Int, role: String) {
        if store.act({ $0.lendWorker(from: from, to: to, role: role) }) == true {
            Haptics.success()
            store.show("A \(role) moved to \(engine.state.company(to)?.name ?? "the store").", tone: "good")
        } else {
            Haptics.warning()
            store.show("That worker could not be moved now.", tone: "warn")
        }
    }
}
