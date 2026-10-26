import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Franchising from both sides: your concept franchised out (units, applicants, master franchises abroad) and, when the company
/// runs under a brand, what the brand asks of you.
struct CompanyFranchise: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !company.value("franchise").isNull { FranchiseeCard(engine: engine, company: company) }
            if engine.canFranchise(companyID: company.id) && company.value("franchise").isNull { FranchisorCard(engine: engine, company: company) }
        }
    }
}

/// You are a franchisee: royalties, the brand's quality standard, the contract, and the way out.
struct FranchiseeCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var confirmLeave = false

    var body: some View {
        let f = company.value("franchise")
        let cur = engine.currency(for: company)
        let minQ = engine.franchiseMinimumQuality(companyID: company.id)
        let buyout = engine.franchiseBuyout(companyID: company.id)
        LedgerSection(title: "Franchise", trailing: { Text(f["brandName"].string).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("You run under a known brand: it brings customers and a name, and you pay for it out of every sale.").font(.caption).foregroundStyle(Theme.ivoryMuted).padding(.bottom, 6)
                FlatRow(label: "Royalty", value: Currency.percent(f["roy"].double, decimals: 1) + " of revenue")
                FlatRow(label: "Marketing fund", value: Currency.percent(f["mkt"].double, decimals: 0) + " of revenue")
                FlatRow(label: "Brand", value: FranchiseBrands.brandWord(f["brand"].double), sub: "Your quality keeps it strong or drags it down.")
                FlatRow(label: "Quality", value: "\(Int(company.quality.rounded())) (brand minimum \(Int(minQ)))", sub: company.quality < minQ ? "Below the standard: the franchisor warns, then ends the contract." : "",
                        tint: company.quality < minQ ? Theme.loss : Theme.ivory)
                if !f["end"].isNull { FlatRow(label: "Contract ends", value: GameCalendar.dateString(week: f["end"].int, dayOffset: 0)) }
                if f["owed"].double > 0.5 { FlatRow(label: "Royalties owed", value: cur.tidyShort(f["owed"].double), sub: "Paid first from the company's cash; unpaid parts pile up.", tint: Theme.loss) }
                Hairline()
                Button("Leave the franchise · buyout \(cur.tidyShort(buyout))") { confirmLeave = true }
                    .font(.system(size: 12.5)).foregroundStyle(Theme.loss).buttonStyle(.plain).padding(.top, 10)
            }
        }
        .confirmationDialog("Leave the franchise?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Pay \(cur.tidyShort(buyout)) and leave", role: .destructive) {
                if store.act({ $0.leaveFranchise(companyID: company.id) }) == true { Haptics.success(); store.show("\(company.name) is now independent.") }
            }
        } message: {
            Text("You pay \(cur.tidyShort(buyout)) to buy out the contract (including any royalties you owe), put up new signs, and lose much of the brand awareness. No more royalties after that.")
        }
    }
}

/// You are the franchisor.
struct FranchisorCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var fee = 0.0
    @State private var royalty = 0.06
    @State private var support = 0
    @State private var masterCountry = ""
    @State private var terminate: Int?

    var body: some View {
        let cur = engine.currency(for: company)
        let on = engine.isFranchisor(companyID: company.id)
        let flag = engine.chainSummary(containing: company.id)?.franchisingCompanyID
        LedgerSection("Franchise your concept") {
            VStack(alignment: .leading, spacing: 0) {
                if let flag, flag != company.id, !on {
                    Text("Franchising runs from one store of the chain.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    NavigationLink(value: CompanyRoute.company(flag)) { Text("Open \(engine.state.company(flag)?.name ?? "that store")  ›").font(.system(size: 13)).foregroundStyle(Theme.gold) }.padding(.top, 6)
                } else if on {
                    running(cur)
                } else {
                    notYet(cur)
                }
            }
        }
        .confirmationDialog("End this contract?", isPresented: Binding(get: { terminate != nil }, set: { if !$0 { terminate = nil } }), titleVisibility: .visible) {
            Button("End contract", role: .destructive) {
                if let u = terminate { store.act { $0.terminateFranchiseUnit(companyID: company.id, unitID: u) }; Haptics.success() }
                terminate = nil
            }
        } message: { Text("The unit loses your brand and stops paying royalties. A lawyer costs \(cur.tidyShort(cur.scaledPrice(15000))) and may recover part of any arrears.") }
    }

    // MARK: Before launch

    @ViewBuilder private func notYet(_ cur: Currency) -> some View {
        let reqs = engine.franchiseRequirements(companyID: company.id)
        let doc = engine.documentState(companyID: company.id, document: "fran")
        Text("Others open units under your name for a fee and royalties, once the chain has proven itself. \(reqs.filter { $0.ok }.count) of \(reqs.count) ready.")
            .font(.caption).foregroundStyle(Theme.ivoryMuted).padding(.bottom, 6)
        ForEach(Array(reqs.enumerated()), id: \.element.id) { n, r in
            if n > 0 { Hairline() }
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: r.ok ? "checkmark" : "circle").font(.system(size: 11)).foregroundStyle(r.ok ? Theme.gain : Theme.ivoryFaint).frame(width: 18)
                Text(r.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                Spacer(minLength: 8)
                Text(r.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.trailing)
            }.padding(.vertical, 8)
        }
        if reqs.allSatisfy({ $0.ok }) {
            Hairline()
            if doc.status == "applied" {
                Text("Franchise documents: about \(doc.weeksLeft) \(doc.weeksLeft == 1 ? "week" : "weeks") left. A lawyer writes the agreement and the disclosure document.").font(.caption).foregroundStyle(Theme.caution).padding(.top, 10)
            } else if doc.status != "ok" {
                Button("Apply for franchise documents · \(cur.tidyShort(engine.documentFee(companyID: company.id, document: "fran")))") {
                    switch store.act({ $0.applyForChainDocument(companyID: company.id, document: "fran") }) {
                    case .ok?: Haptics.success(); store.show("Application sent.", tone: "good")
                    case .notYet(let why)?: store.show(why, tone: "warn")
                    case .notEnoughCash?: store.show("Not enough cash in the company for the lawyer.", tone: "warn")
                    default: break
                    }
                }.buttonStyle(QuietButtonStyle()).padding(.top, 10)
            } else {
                launchForm(cur)
            }
        }
    }

    @ViewBuilder private func launchForm(_ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Terms for new units").font(.caption).foregroundStyle(Theme.ivoryMuted)
            HStack {
                Text("Entry fee").font(.system(size: 13.5)); Spacer()
                ForEach([50_000.0, 150_000, 300_000], id: \.self) { v in
                    let amt = cur.scaledPrice(v)
                    Button(cur.tidyShort(amt)) { fee = amt }.buttonStyle(QuietButtonStyle(tint: abs(fee - amt) < 1 ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Royalty").font(.system(size: 13.5)); Spacer()
                ForEach([0.04, 0.06, 0.08, 0.10], id: \.self) { v in
                    Button("\(Int(v * 100))%") { royalty = v }.buttonStyle(QuietButtonStyle(tint: abs(royalty - v) < 0.0001 ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Set-up").font(.system(size: 13.5)); Spacer()
                Button("Franchisee pays") { support = 0 }.buttonStyle(QuietButtonStyle(tint: support == 0 ? Theme.gold : Theme.ivoryFaint))
                Button("Half covered") { support = 1 }.buttonStyle(QuietButtonStyle(tint: support == 1 ? Theme.gold : Theme.ivoryFaint))
            }
            Button("Launch franchise") {
                let f = fee > 0 ? fee : cur.scaledPrice(150_000)
                if store.act({ $0.launchFranchise(companyID: company.id, entryFee: f, royalty: royalty, support: support) }) == .ok { Haptics.success(); store.show("Franchise launched.", tone: "good") }
            }.buttonStyle(GoldButtonStyle()).padding(.top, 6)
            Text("Applicants come as the brand grows. You agree the terms with each one in a talk; units pay the fee and royalties, struggle, renew, leave or are ended.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
        }.padding(.top, 10)
    }

    // MARK: Running

    @ViewBuilder private func running(_ cur: Currency) -> some View {
        let f = engine.franchiseSystem(companyID: company.id)
        let units = f["units"].array
        let apps = engine.franchiseApplicants(companyID: company.id)
        KeyFigures(items: [
            .init(label: "Brand", value: FranchiseBrands.brandWord(f["brand"].double)),
            .init(label: "Units open", value: "\(units.count)"),
            .init(label: "Income last week", value: cur.tidyShort(f["income"].double)),
            .init(label: "Fee", value: cur.tidyShort(f["fee"].double)),
            .init(label: "Royalty", value: Currency.percent(f["roy"].double, decimals: 0)),
            .init(label: "Set-up", value: ["Franchisee pays", "Half covered", "Fully covered"][min(2, f["supp"].int)]),
        ])
        if !units.isEmpty {
            Text("Units").capsLabel(Theme.ivoryFaint).padding(.top, 10)
            ForEach(Array(units.enumerated()), id: \.offset) { n, u in
                if n > 0 { Hairline() }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(u["name"].string).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text("\(engine.data.countries.city(u["city"].string, preferring: company.countryCode)?.city.name ?? "")\(u["owed"].double > 0.5 ? " · owes \(cur.tidyShort(u["owed"].double))" : "") · until \(GameCalendar.dateString(week: u["end"].int, dayOffset: 0))")
                            .font(.system(size: 11)).foregroundStyle(u["owed"].double > 0.5 ? Theme.loss : Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(cur.tidyShort(u["rev"].double) + " / wk").font(.system(size: 13.5).monospacedDigit()).foregroundStyle(u["prof"].double < 0 ? Theme.loss : Theme.ivory)
                        Button("End contract") { terminate = u["id"].int }.font(.system(size: 11.5)).foregroundStyle(Theme.loss).buttonStyle(.plain)
                    }
                }.padding(.vertical, 9)
            }
        }
        Text("Applicants").capsLabel(Theme.ivoryFaint).padding(.top, 10)
        if apps.isEmpty {
            Text("No applicants right now. Brand strength attracts more.").font(.caption).foregroundStyle(Theme.ivoryFaint).padding(.top, 4)
        }
        ForEach(Array(apps.enumerated()), id: \.element.id) { n, a in
            if n > 0 { Hairline() }
            NavigationLink { FranchiseTalkView(companyID: company.id, applicantID: a.id) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text("\(engine.data.countries.city(a.cityID, preferring: company.countryCode)?.city.name ?? "") · \(a.experience) yr experience · own money \(cur.tidyShort(a.capital))")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer()
                    Text("Talk  ›").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                }.padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        let masters = f["masters"].array
        let countries = engine.masterFranchiseCountries(companyID: company.id).filter { c in !masters.contains { $0["c"].string == c.code } }
        Text("Master franchise").capsLabel(Theme.ivoryFaint).padding(.top, 10)
        ForEach(Array(masters.enumerated()), id: \.offset) { n, m in
            let c = engine.data.countries[m["c"].string]
            FlatRow(label: "\(c?.flag ?? "") \(c?.name ?? m["c"].string)", value: engine.state.week < m["ready"].int ? "registering, \(m["ready"].int - engine.state.week) wk" : "\(m["n"].int) units · \(cur.tidyShort(m["rev"].double)) / wk")
        }
        if !countries.isEmpty {
            Text("Sell a whole country to a local partner: a big fee up front and half the royalties. Legal work is slower and costlier in complex countries.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            HStack {
                Picker("Country", selection: Binding(get: { masterCountry.isEmpty ? countries[0].code : masterCountry }, set: { masterCountry = $0 })) {
                    ForEach(countries) { Text("\($0.flag) \($0.name)").tag($0.code) }
                }.pickerStyle(.menu)
                Spacer()
                Button("Sell master franchise") {
                    switch store.act({ $0.sellMasterFranchise(companyID: company.id, country: masterCountry.isEmpty ? countries[0].code : masterCountry) }) {
                    case .ok?: Haptics.success(); store.show("Master franchise signed.", tone: "good")
                    case .cash?: store.show("Not enough cash for the legal work.", tone: "warn")
                    case .banned(let why)?: store.show(why, tone: "warn")
                    default: store.show("Not possible.", tone: "warn")
                    }
                }.buttonStyle(QuietButtonStyle())
            }
        }
    }
}

/// The talk with one applicant: an offer, their answer, until they sign, give up, or you do.
struct FranchiseTalkView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var applicantID: Int
    @State private var terms = Franchising.TalkTerms()
    @State private var loaded = false
    @State private var log: [(mine: Bool, text: String)] = []
    @State private var finished = false
    @State private var applicantCopy: Franchising.Applicant?
    @State private var patience = 3

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let a = e.franchiseApplicants(companyID: companyID).first(where: { $0.id == applicantID }) ?? applicantCopy {
            let cur = e.currency(for: co)
            let sums = e.talkSums(companyID: companyID, applicantID: applicantID, terms: terms)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text("\(e.data.countries.city(a.cityID, preferring: co.countryCode)?.city.name ?? "") · \(a.experience) yr experience · \(a.personalityText)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        bubble(false, "Hello. \(a.experience > 0 ? "I have \(a.experience) \(a.experience == 1 ? "year" : "years") in \(e.tradeName(co).lowercased())" : "I am new to \(e.tradeName(co).lowercased()), but I learn fast") and would like to open a \(co.name) in \(e.data.countries.city(a.cityID, preferring: co.countryCode)?.city.name ?? ""). I have \(cur.tidyShort(a.capital)) of my own; the setup is about \(cur.tidyShort(sums?.setup ?? 0)).")
                        ForEach(Array(log.enumerated()), id: \.offset) { _, l in bubble(l.mine, l.text) }
                    }
                    if !finished {
                        LedgerSection("Your offer") {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                choice("Entry fee · \(cur.tidyShort(co.value("fr")["fee"].double * terms.feeFactor))", [(1.0, "Full"), (0.5, "Half"), (0.0, "Waived")], current: terms.feeFactor) { terms.feeFactor = $0 }
                                choice("Royalty of sales", [0.04, 0.05, 0.06, 0.07, 0.08, 0.10].map { ($0, "\(Int($0 * 100))%") }, current: terms.royalty) { terms.royalty = $0 }
                                HStack {
                                    Text("Your help with the setup").font(.caption).foregroundStyle(Theme.ivoryMuted); Spacer()
                                }
                                HStack {
                                    ForEach([("none", "None"), ("l25", "Lend 25%"), ("l50", "Lend 50%"), ("c50", "Cover half")], id: \.0) { h in
                                        Button(h.1) { terms.help = h.0 }.buttonStyle(QuietButtonStyle(tint: terms.help == h.0 ? Theme.gold : Theme.ivoryFaint)).font(.caption)
                                    }
                                }
                                if terms.help == "c50" {
                                    choice("Your share of their profit", [(0.25, "25%"), (0.45, "45%"), (0.6, "60%")], current: terms.profitShare) { terms.profitShare = $0 }
                                }
                                choice("Contract", [(5.0, "5 years"), (10.0, "10 years")], current: Double(terms.years)) { terms.years = Int($0) }
                                if let s = sums {
                                    Hairline()
                                    FlatRow(label: "They need", value: cur.tidyShort(max(0, s.need)), sub: "They have \(cur.tidyShort(a.capital)) of their own.", tint: a.capital < s.need ? Theme.loss : Theme.ivory, rule: false)
                                    FlatRow(label: "Their profit a year", value: cur.tidyShort(s.theirs), tint: s.theirs < 0 ? Theme.loss : Theme.ivory)
                                    FlatRow(label: "Yours a year", value: cur.tidyShort(s.yours), sub: s.youPutIn > 0 ? "You put in \(cur.tidyShort(s.youPutIn))." : "")
                                }
                                Text("Patience " + String(repeating: "●", count: max(0, patience)) + String(repeating: "○", count: max(0, (Franchising.patienceDots(for: a.personality)) - max(0, patience))))
                                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                Button("Send offer") { send(a, co: co, cur: cur) }.buttonStyle(GoldButtonStyle())
                            }
                        }
                    } else {
                        Button("Back to the franchise") { dismiss() }.buttonStyle(GoldButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Franchise applicant")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !loaded { terms = e.standardTalkTerms(companyID: companyID); applicantCopy = a; patience = a.patience; loaded = true }
            }
        } else {
            Text("This applicant has moved on.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func bubble(_ mine: Bool, _ text: String) -> some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(text).font(.system(size: 13.5)).foregroundStyle(mine ? Theme.ivory : Theme.ivoryMuted).padding(.vertical, 6)
                .overlay(alignment: mine ? .trailing : .leading) { Rectangle().fill(mine ? Theme.gold : Theme.hairline).frame(width: 1.5) }
                .padding(.horizontal, 10)
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func choice(_ title: String, _ options: [(Double, String)], current: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.ivoryMuted)
            WrapRow {
                Group {
                    ForEach(options, id: \.0) { o in
                        Button(o.1) { set(o.0) }.buttonStyle(QuietButtonStyle(tint: abs(current - o.0) < 0.0001 ? Theme.gold : Theme.ivoryFaint)).font(.caption)
                    }
                }
            }
        }
    }

    private func send(_ a: Franchising.Applicant, co: Company, cur: Currency) {
        let helpText: [String: String] = ["none": "no help with the setup", "l25": "a loan of a quarter of the setup", "l50": "a loan of half of the setup", "c50": "half of the setup covered for \(Int(terms.profitShare * 100))% of the profit"]
        log.append((true, "Fee \(terms.feeFactor == 1 ? "in full" : terms.feeFactor > 0 ? "half" : "waived"), \(Int(terms.royalty * 100))% royalty, \(helpText[terms.help] ?? ""), \(terms.years) years."))
        guard let r = store.act({ $0.offerToApplicant(companyID: companyID, applicantID: applicantID, terms: terms) }) ?? nil else { return }
        log.append((false, r.answer.text))
        if let n = r.note { log.append((false, n)) }
        if r.signed { finished = true; Haptics.success(); store.show("\(a.name) signed. The unit opens.", tone: "good") }
        else {
            patience -= 1
            if let hint = r.answer.hint { terms.help = hint }
            if r.walkedAway { finished = true; Haptics.warning() }
        }
    }
}
