import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A hand-drawn signature: the player draws with a finger. `strokes` holds every line drawn.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PopupRadius.inner, style: .continuous).fill(Color.white.opacity(0.94))
            Canvas { ctx, _ in
                for s in strokes where s.count > 1 {
                    var p = Path(); p.addLines(s)
                    ctx.stroke(p, with: .color(Color(red: 0.08, green: 0.1, blue: 0.3)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
            }
            if strokes.isEmpty { Text("Sign here with your finger").font(.system(size: 13)).foregroundStyle(Color.black.opacity(0.35)) }
        }
        .frame(height: 110)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { (v: DragGesture.Value) in
                if v.translation == .zero || strokes.isEmpty { strokes.append([v.location]) } else { strokes[strokes.count - 1].append(v.location) }
            })
        .accessibilityLabel("Signature box")
    }
}

/// The paper form for a document or licence application: what it is, who issues it, the fee and the wait, a box to confirm the terms and a
/// signature box. Only when both are done can it be sent; the authority then reviews it and answers later (it may refuse).
struct DocumentSignSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var documentID: String
    var onClose: () -> Void

    var body: some View {
        Group {
            if let f = form, let co = store.engine?.state.company(companyID) {
                SignPopup(title: f.name, to: f.issuer.tidyText, note: f.note,
                          fee: f.fee > 0 ? store.short(f.fee, in: co) : "Free",
                          wait: "in about \(max(1, f.weeks)) week\(f.weeks == 1 ? "" : "s")",
                          button: f.status == "rejected" ? "Sign and apply again" : "Sign and send",
                          caption: "The authority reviews it and answers by message. It can refuse; you may then apply again at once.",
                          closesFirst: false, onSend: { send(f, co) }, onClose: onClose)
            }
        }
        .centerSheetTitle(form?.name ?? "Application")
        .centerSheetLocked()
    }

    private var form: DocumentForm? { store.engine?.documentForm(companyID: companyID, documentID: documentID) }

    private func send(_ f: DocumentForm, _ co: Company) {
        let r = store.act { $0.applyForDocument(companyID: companyID, documentID: documentID) }
        switch r {
        case .ok?: Haptics.success(); store.show("\(f.name): sent. The answer comes in about \(max(1, f.weeks)) week\(f.weeks == 1 ? "" : "s").", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in \(co.name) for the \(store.short(f.fee, in: co)) fee.", tone: "warn")
        default: Haptics.warning(); store.show("That application is already in.", tone: "warn")
        }
        onClose()
    }
}

/// Manage > Licences: the papers the choices in How you sell need. Apply by signing the form; the answer comes later and may be a refusal.
struct CompanyLicences: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var signing: String?

    var body: some View {
        let lines: [LicenceLine] = engine.licences(companyID: company.id)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Licences let you add new things to sell. Apply here; once one is held, switch the product on in Sales > How you sell.")
                .popupText(.subtitle)
            ForEach(lines) { (l: LicenceLine) in card(l) }
            if lines.isEmpty { Text("This business has no licences to add.").popupText(.caption) }
        }
        .centerSheet(isPresented: Binding(get: { signing != nil }, set: { if !$0 { signing = nil } })) {
            if let id = signing { DocumentSignSheet(companyID: company.id, documentID: id) { signing = nil }.environment(\.outsidePalette, OutsidePalette.game).presentationBackground(.clear) }
        }
    }

    private func statusText(_ f: DocumentForm) -> (String, Color) {
        switch f.status {
        case "ok": return ("Held", Theme.gain)
        case "applied": return ("Under review" + (f.answerWeek.map { " \u{00B7} answer in week \($0)" } ?? ""), Theme.warn)
        case "rejected": return ("Refused: apply again", Theme.loss)
        case "lapsed": return ("Lapsed: apply again", Theme.loss)
        default: return ("Not applied", Theme.inkSoft)
        }
    }

    private func card(_ l: LicenceLine) -> some View {
        let s = statusText(l.form)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(l.form.name).popupText(.rowValue)
                Spacer(minLength: Theme.Space.s)
                Text(s.0).textStyle(.caption, tint: s.1)
            }
            Text("Unlocks: " + l.unlocks.joined(separator: ", ")).popupText(.subtitle)
            Text((l.form.fee > 0 ? "Fee " + store.short(l.form.fee, in: company) : "Free") + " \u{00B7} review about \(max(1, l.form.weeks)) week\(l.form.weeks == 1 ? "" : "s")")
                .popupText(.caption)
            if ["", "rejected", "lapsed"].contains(l.form.status) {
                Button(l.form.status == "" ? "Fill in and apply" : "Apply again") { Haptics.tap(); signing = l.id }.buttonStyle(QuietButtonStyle())
            } else if l.form.status == "ok" {
                Button("Add the product in How you sell") { store.openCompany(company.id, section: .salesMarket) }.buttonStyle(QuietButtonStyle())
            }
        }
        .padding(Theme.Space.l).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surface))
    }
}
