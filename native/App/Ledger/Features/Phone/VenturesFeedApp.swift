import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

/// The Ventures phone app, drawn as a startup feed: every pitch on offer is a post with a logo, the pitch line, the ask, the traction
/// and a "Back it" action; your stakes in other founders' startups come as posts too, with Help the team and Sell. The other kinds of
/// venture (your own startups, funds, group stakes, software) sit below the feed in the existing `VenturesContent`.
/// Engine calls: `startupPitchesOnOffer`, `startupStakes`, `investInStartup`, `helpStartupOnBoard`, `sellStartupStake`.
struct VenturesFeedApp: View {
    private var P: OutsidePalette { .ventures }
    @EnvironmentObject var store: GameStore
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(e, cur)
                    feedLabel("New pitches", note: "new ones every four weeks")
                    pitches(e, cur)
                    stakes(e, cur)
                    feedLabel("More ventures", note: "")
                    VenturesContent(hidesBacking: true)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .outsideScreen(P)
            .confirmAction($pending)
            .accessibilityIdentifier("ventures-app")
        }
    }

    // MARK: Header

    private func header(_ e: GameEngine, _ cur: Currency) -> some View {
        let held: [Startups.Stake] = e.startupStakes.filter { $0.live }
        let value: Double = held.reduce(0) { $0 + $1.value }
        return HStack(alignment: .center, spacing: 12) {
            OutsideBack()
            VStack(alignment: .leading, spacing: 1) {
                Text("Ventures").font(.serifTitle(26)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                Text(held.isEmpty ? "Founders looking for money" : "\(held.count) backed · " + cur.tidyShort(value) + " at paper value")
                    .font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
            }
            Spacer(minLength: 0)
        }
    }

    private func feedLabel(_ title: String, note: String) -> some View {
        HStack {
            Text(title.uppercased()).capsLabel()
            Spacer()
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(P.inkFaint) }
        }
        .padding(.top, 4)
    }

    // MARK: Pitch posts

    @ViewBuilder private func pitches(_ e: GameEngine, _ cur: Currency) -> some View {
        let list: [Startups.Pitch] = e.startupPitchesOnOffer
        let minimum: Double = cur.scaledPrice(Startups.minimumInvestment)
        if list.isEmpty {
            NoteCard(text: "No founder is pitching right now. New pitches arrive every four weeks.", glyph: Glyph.ventures)
        }
        ForEach(list) { (p: Startups.Pitch) in pitchPost(p, cur, minimum) }
        if !list.isEmpty {
            Text("The smallest cheque is \(cur.tidyShort(minimum)). Twenty percent or more brings a board seat, where you can help the team. Most young companies fail.")
                .font(.system(size: 11)).foregroundStyle(P.inkFaint)
        }
    }

    private func logo(_ name: String, _ sector: String) -> some View {
        ThumbnailView(kind: .trade, key: sector, size: 46, shape: .square, glyph: Glyph.ventures, initials: name)
    }

    private func pitchPost(_ p: Startups.Pitch, _ cur: Currency, _ minimum: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                logo(p.name, p.sector)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(P.ink)
                    Text(p.sector).font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
                }
                Spacer(minLength: 8)
                Text("PITCHING").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(P.accent2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(P.accent2.opacity(0.6), lineWidth: 1))
            }
            Text("“" + p.blurb.tidyMoney + "”").font(.system(size: 15, design: .serif)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
            askLine(p, cur)
            tractionRow(p)
            HStack {
                Spacer()
                backMenu(p, cur, minimum)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func askLine(_ p: Startups.Pitch, _ cur: Currency) -> some View {
        HStack(spacing: 0) {
            fact("The ask", cur.tidyShort(p.raise))
            Rectangle().fill(P.line).frame(width: 1, height: 30)
            fact("Valuation before", cur.tidyShort(p.preMoney))
            Rectangle().fill(P.line).frame(width: 1, height: 30)
            fact("After the round", cur.tidyShort(p.postMoney))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(P.divider).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(P.divider).frame(height: 1) }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink)
            Text(label).font(.system(size: 10.5)).foregroundStyle(P.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func tractionRow(_ p: Startups.Pitch) -> some View {
        HStack(spacing: 12) {
            meter("Team", p.team)
            meter("Market", p.market)
            meter("Traction", p.traction)
        }
    }

    private func meter(_ label: String, _ value: Int) -> some View {
        let frac: CGFloat = CGFloat(min(1, max(0, Double(value) / 100)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 10.5)).foregroundStyle(P.inkFaint)
                Spacer(minLength: 2)
                Text("\(value)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(P.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(P.divider)
                    Capsule().fill(P.accent).frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func cheques(_ p: Startups.Pitch, _ minimum: Double) -> [Double] {
        var out: [Double] = []
        for f in [0.1, 0.25, 0.5, 1.0] {
            let a = (p.raise * f / 10000).rounded() * 10000
            if a >= minimum, !out.contains(a) { out.append(a) }
        }
        return out
    }

    private func backMenu(_ p: Startups.Pitch, _ cur: Currency, _ minimum: Double) -> some View {
        let sizes: [Double] = cheques(p, minimum)
        return Menu {
            ForEach(sizes, id: \.self) { (amt: Double) in
                Button("Invest " + cur.tidyShort(amt)) { confirmInvest(p, amt, cur) }
            }
        } label: {
            HStack(spacing: 6) {
                GlyphView(glyph: Glyph.ventures, size: 14, weight: 1.6, tint: P.accent)
                Text("Back it").font(.system(size: 14, weight: .semibold)).foregroundStyle(P.accent)
            }
            .padding(.horizontal, 18).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(P.accent, lineWidth: 1))
        }
        .disabled(sizes.isEmpty)
        .accessibilityLabel("Back \(p.name)")
    }

    private func confirmInvest(_ p: Startups.Pitch, _ amt: Double, _ cur: Currency) {
        let pct = p.postMoney > 0 ? amt / p.postMoney * 100 : 0
        pending = PendingAction(title: "Invest \(cur.tidyShort(amt)) in \(p.name)?",
                                message: "You get about \(String(format: "%.1f", pct))% of it" + (pct >= 20 ? " and a board seat" : "") + ". The money is locked until a sale or exit; later rounds make your share smaller, and most young companies fail.",
                                button: "Invest") {
            switch store.act({ $0.investInStartup(pitchID: p.id, amount: amt) }) {
            case .ok?: Haptics.success(); store.show("You invested \(cur.tidyShort(amt)) in \(p.name).", tone: "good")
            case .tooSmall?: store.show("They want a bigger cheque.", tone: "warn")
            case .notEnoughMoney?: Haptics.warning(); store.show("Not enough cash.", tone: "warn")
            default: store.show("The round has closed.", tone: "warn")
            }
        }
    }

    // MARK: Stakes as posts

    @ViewBuilder private func stakes(_ e: GameEngine, _ cur: Currency) -> some View {
        let list: [Startups.Stake] = e.startupStakes
        if !list.isEmpty {
            feedLabel("Your portfolio", note: "\(list.filter { $0.live }.count) live")
            ForEach(list) { (st: Startups.Stake) in stakePost(st, cur) }
        }
    }

    private func stakePost(_ st: Startups.Stake, _ cur: Currency) -> some View {
        let gain: Double = st.value - st.invested
        let status: String = st.live ? st.stageName : (st.failed ? "Failed" : "Sold")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                logo(st.name, st.sector)
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink)
                    Text("\(st.sector) · \(status) · \(String(format: "%.1f", st.ownership))%" + (st.boardSeat ? " · board seat" : ""))
                        .font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cur.tidyShort(st.value)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink)
                    Text((gain >= 0 ? "▲ +" : "▼ −") + cur.tidyShort(abs(gain))).font(.system(size: 11).monospacedDigit()).foregroundStyle(P.change(gain))
                }
            }
            if st.live { stakeActions(st, cur) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }

    private func stakeActions(_ st: Startups.Stake, _ cur: Currency) -> some View {
        HStack(spacing: 8) {
            if st.boardSeat {
                Button("Help the team") {
                    let ok = store.act { $0.helpStartupOnBoard(stakeID: st.id) } ?? false
                    store.show(ok ? "You spent time with the team." : "You helped recently.", tone: ok ? "good" : "n")
                }.buttonStyle(GreyOutlineButtonStyle())
            }
            ForEach([0.5, 1.0], id: \.self) { (f: Double) in
                Button(f == 1 ? "Sell all" : "Sell half") { confirmSell(st, f, cur) }.buttonStyle(GreyOutlineButtonStyle())
            }
        }
    }

    private func confirmSell(_ st: Startups.Stake, _ f: Double, _ cur: Currency) {
        pending = PendingAction(title: f == 1 ? "Sell your stake in \(st.name)?" : "Sell half your stake in \(st.name)?",
                                message: "A buyer of private shares pays below the paper value of about \(cur.tidyShort(st.value * f)). A gain is taxed.", button: "Sell") {
            let v = store.act { $0.sellStartupStake(stakeID: st.id, fraction: f) } ?? 0
            store.show(v > 0 ? "Sold for \(cur.tidyShort(v))." : "No buyer.", tone: v > 0 ? "good" : "warn")
        }
    }
}
