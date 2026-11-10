import SwiftUI
import GameCore
import Businesses
import Simulation

extension Glyph {
    static let rivalsFlag = "M7 4 V20 M7 5 H18 L15 8.5 L18 12 H7"
    static let moveUp = "M12 19 V5 M6 11 L12 5 L18 11"
    static let moveDown = "M12 5 V19 M6 13 L12 19 L18 13"
}

struct EffectArrow: View {
    var effect: Int
    var size: CGFloat = 16

    var body: some View {
        if effect == 0 {
            Color.clear.frame(width: size, height: size)
        } else {
            GlyphView(glyph: effect > 0 ? Glyph.moveUp : Glyph.moveDown, size: size, weight: 1.8, tint: effect > 0 ? Theme.gain : Theme.loss)
                .accessibilityElement()
                .accessibilityLabel(effect > 0 ? "Good for you" : "Against you")
        }
    }
}

struct RivalsApp: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            PhonePageScroll(spacing: Theme.Space.xl) {
                if !e.rivalsOpen {
                    NoteCard(text: "Rivals open after a few months of trading, once you have a place in the market.")
                } else {
                    let markets = e.rivalMarkets()
                    decisions(e)
                    if markets.isEmpty {
                        NoteCard(text: "No rivals are written down yet. They appear in the weeks after a company opens.")
                    }
                    ForEach(markets) { (m: RivalMarket) in
                        CardSection(m.title) {
                            ForEach(Array(m.cards.enumerated()), id: \.element.id) { i, c in
                                if i > 0 { CardLine() }
                                rivalBlock(c)
                            }
                        }
                    }
                    if let first = markets.first {
                        recent(e, companyID: first.companyID)
                    }
                }
            }
        }
    }

    @ViewBuilder private func decisions(_ e: GameEngine) -> some View {
        let open: [Message] = e.openDecisions.filter { (m: Message) -> Bool in RivalStories.handlesAnswer(m.actionID) }
        if !open.isEmpty {
            CardSection("Waiting for you") {
                ForEach(open, id: \.id) { (m: Message) in
                    LedgerRow(leading: .glyph(Glyph.rivalsFlag), title: m.title, subtitle: "Take your time: it stays until you answer or it lapses.", action: { store.decisionPopup = m.id })
                }
            }
        }
    }

    private func rivalBlock(_ c: RivalStories.Card) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(c.name).textStyle(.headline)
                Spacer(minLength: 8)
                EffectArrow(effect: c.trend)
            }
            Text("\(c.trade) in \(c.city). Run by \(c.owner).").textStyle(.caption)
            HStack(spacing: Theme.Space.l) {
                fact("Against you", c.standing)
                fact("Doing", c.health)
                fact("Towards you", c.mood)
            }
            if c.forSale {
                Text("Might sell if the price is right.").textStyle(.caption, tint: Theme.accent)
            }
            if !c.moves.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(c.moves.prefix(3)) { (m: RivalStories.Move) in moveLine(m) }
                }
                .padding(.top, Theme.Space.xxs)
            } else {
                Text("Nothing to report lately.").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .contain)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textStyle(.label)
            Text(value).textStyle(.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moveLine(_ m: RivalStories.Move) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            EffectArrow(effect: m.effect, size: 14)
            Text(m.text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text(GameCalendar.dateString(week: m.week)).textStyle(.caption, tint: Theme.inkFaint)
        }
    }

    private func recent(_ e: GameEngine, companyID: Int) -> some View {
        let moves: [RivalStories.Move] = e.rivalMoves(companyID: companyID, limit: 12)
        return CardSection("Lately") {
            if moves.isEmpty {
                Text("Quiet. Rivals move slowly, a few times a year.").textStyle(.caption)
            } else {
                ForEach(Array(moves.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { CardLine() }
                    moveLine(m)
                }
            }
        }
    }
}
