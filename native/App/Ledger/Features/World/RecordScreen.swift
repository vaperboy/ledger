import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct RecordScreen: View {
    var e: GameEngine
    var r: WorldRead
    var back: () -> Void
    @State private var tab = 0
    private let P: OutsidePalette = .docket
    private let mono: Font = .system(size: 12, weight: .semibold, design: .monospaced)

    private var justice: Justice { r.world.justice }

    var body: some View {
        CivicPage(spacing: 18) {
            CivicHeader(title: "Record", subtitle: "Convictions and the public watchlist", onBack: back)
            tabs
            if tab == 0 { mine } else { watch }
        }
        .outsideScreen(.docket)
        .accessibilityIdentifier("world-record")
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton(0, "My record", Glyph.gavel)
            tabButton(1, "Watchlist", Glyph.watchEye)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.cardDeep))
    }

    private func tabButton(_ i: Int, _ title: String, _ glyph: String) -> some View {
        Button {
            Haptics.choose()
            tab = i
        } label: {
            HStack(spacing: 8) {
                GlyphView(glyph: glyph, size: 16, weight: 1.8, tint: tab == i ? P.onAccent : P.inkSoft)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(tab == i ? P.onAccent : P.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tab == i ? P.accent2 : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(tab == i ? .isSelected : [])
    }

    private var mine: some View {
        let list: [PlayerConviction] = justice.own(r.account)
        let standing: Int = justice.count(r.account)
        return VStack(alignment: .leading, spacing: 16) {
            bans
            HStack {
                Text("CASES").font(mono).tracking(2).foregroundStyle(P.inkFaint)
                Spacer(minLength: 8)
                Text("\(standing) standing").font(mono).foregroundStyle(standing > 0 ? P.loss : P.inkFaint)
            }
            if list.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A clean record").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                    Text("No convictions stand against you.").textStyle(.body)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.line, lineWidth: 1))
            } else {
                ForEach(list) { (c: PlayerConviction) in caseCard(c) }
            }
            Text("Other players see only how many convictions stand against you. Only grave cases are named on the watchlist.")
                .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bans: some View {
        let rows: [(String, Justice.Scope)] = [("Trading", .trade), ("Standing for office", .office), ("Voting", .vote)]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { (i: Int, row: (String, Justice.Scope)) in
                let on: Bool = justice.barred(r.account, row.1, week: r.week)
                if i > 0 { Rectangle().fill(P.hairline).frame(height: 1) }
                HStack {
                    Text(row.0).textStyle(.body)
                    Spacer(minLength: 8)
                    if on, let until = banEnd(row.1) {
                        CivicTag(text: "Barred until \(CivicWords.date(until))", tint: P.loss)
                    } else {
                        CivicTag(text: "Free", tint: P.gain)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.line, lineWidth: 1))
    }

    private func banEnd(_ scope: Justice.Scope) -> Int? {
        let ends: [Int] = justice.own(r.account).compactMap { (c: PlayerConviction) -> Int? in
            guard !c.quashed else { return nil }
            switch scope { case .trade: return c.tradeBanUntil; case .office: return c.officeBanUntil; case .vote: return c.voteBanUntil }
        }
        return ends.max()
    }

    private func caseCard(_ c: PlayerConviction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CASE No. " + String(format: "%04d", c.id)).font(mono).tracking(1.5).foregroundStyle(P.inkFaint)
                Spacer(minLength: 8)
                if c.grave { CivicTag(text: "Grave", tint: P.loss, filled: true, onFill: P.onAccent) }
            }
            Text(CivicWords.offence(c.kind)).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
            Text(c.summary).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(P.hairline).frame(height: 1)
            fact("Decided", CivicWords.date(c.week))
            fact("Fine", c.fine > 0 ? r.cur.tidyDisplay(c.fine) : "None")
            if let t = c.tradeBanUntil { fact("Trading ban", banText(t, c)) }
            if let o = c.officeBanUntil { fact("Office ban", banText(o, c)) }
            if let v = c.voteBanUntil { fact("Voting ban", banText(v, c)) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.lineStrong.opacity(0.5), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if c.quashed {
                Text("QUASHED").font(.system(size: 20, weight: .heavy)).tracking(3).foregroundStyle(P.gain)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.gain, lineWidth: 2.5))
                    .rotationEffect(.degrees(-9)).padding(.top, 40).padding(.trailing, 14)
            }
        }
        .opacity(c.quashed ? 0.8 : 1)
    }

    private func banText(_ until: Int, _ c: PlayerConviction) -> String {
        if c.quashed { return "Ended, conviction quashed" }
        return until > r.week ? "Until \(CivicWords.date(until))" : "Served"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).textStyle(.caption)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(P.ink).multilineTextAlignment(.trailing)
        }
    }

    private var watch: some View {
        let list: [WatchlistEntry] = justice.watchlist
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    GlyphView(glyph: Glyph.watchEye, size: 20, weight: 1.6, tint: P.accent)
                    Text("PUBLIC WATCHLIST").font(mono).tracking(2).foregroundStyle(P.accent)
                }
                Text("Anyone convicted of a grave offence is named here. A conviction that is overturned removes the name.")
                    .textStyle(.body).fixedSize(horizontal: false, vertical: true)
            }
            if list.isEmpty {
                Text("No one is on the list.").textStyle(.body)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.line, lineWidth: 1))
            } else {
                ForEach(list) { (w: WatchlistEntry) in entry(w) }
            }
        }
    }

    private func entry(_ w: WatchlistEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Rectangle().fill(P.cardDeep)
                GlyphView(glyph: Glyph.person, size: 30, weight: 1.4, tint: P.inkDim)
            }
            .frame(width: 64, height: 76)
            .overlay(Rectangle().strokeBorder(P.lineStrong.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(r.shown(w.name, account: w.account)).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                Text(CivicWords.offence(w.kind).uppercased()).font(mono).tracking(1.5).foregroundStyle(P.loss)
                Text(w.summary).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                Text("Listed " + CivicWords.date(w.week)).textStyle(.caption, tint: P.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
