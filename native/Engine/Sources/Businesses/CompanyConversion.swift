import Foundation
import GameCore
import Countries
import Finance

/// Turning a sole trader into a limited company, as ONE transaction (Stage 2, financial.md C1-C10).
///
/// What the old flag-flip missed and this does:
///  - the owner pays the share capital personally; the player chooses who pays the FEE (personal or company account),
///    and the chosen account is checked (personal means current account plus savings, as every personal payment);
///  - the part of the tax year before the conversion is closed into the owner's personal return
///    (`PersonalTaxYear.soleTraderFrozenProfit`) and the corporate tax base opens at zero, so no profit falls between the two regimes;
///  - what the owner put in is carried as contributed capital (`injectedCapital`), so the dividend shield is right;
///  - an accountant is appointed with the agreement document, because the legal form requires it (`Documents.needed`);
///  - the legal identity is recorded (`legal`: form, name, shares, history) and the name takes the form's ending;
///  - loans keep the personal guarantee (banks require it); `LoanGuarantee` is the renegotiation path;
///  - the value does not change by converting (the old 0.85 goodwill discount is gone from `Valuation`).
/// `plan` is a dry run of the same code on a copy, so the preview cannot disagree with the result.
public enum CompanyConversion {
    /// Shares issued to the owner at conversion.
    static let shareTotal = 100.0
    public enum Payer: String, CaseIterable, Sendable { case personal, company }

    public struct PayerOption: Equatable, Sendable, Identifiable {
        public var id: String { payer.rawValue }
        public var payer: Payer
        public var accountName: String
        /// What the account holds (personal: current account only).
        public var balance: Double
        /// What can actually be drawn: personal = current account + savings; company = its cash.
        public var spendable: Double
        /// What this option must cover in total (personal also covers the share capital).
        public var needed: Double
        public var affordable: Bool
        public var shortfall: Double
    }

    public struct LoanLine: Equatable, Sendable, Identifiable {
        public var id: Int { loanID }
        public var loanID: Int
        public var name: String
        public var balance: Double
        public var personallyGuaranteed: Bool
    }

    public enum Block: Equatable, Sendable {
        case alreadyLimited, notTrading, chainStore, unknownCountry
        public var text: String {
            switch self {
            case .alreadyLimited: return "This company is already a limited company."
            case .notTrading: return "Only a company that is trading or being set up can change its legal form."
            case .chainStore: return "A store of a chain follows the chain's legal form."
            case .unknownCountry: return "The company's country has no rules for a limited company."
            }
        }
    }

    public struct Plan: Equatable, Sendable {
        public var companyID: Int
        public var companyName: String
        public var blocked: Block?
        public var fee: Double
        public var shareCapital: Double
        public var payer: Payer
        public var payerOptions: [PayerOption]
        /// The chosen option can pay (and the owner can pay the capital).
        public var affordable: Bool
        public var accountToCharge: String
        public var currentFormName: String
        public var newFormName: String
        public var nameBefore: String
        public var nameAfter: String
        /// The accountant the legal form requires (existing one kept) and its monthly fee.
        public var accountantName: String
        public var accountantMonthlyFee: Double
        public var accountantRequired: Bool
        /// Sole-trader profit of the year so far, closed into the personal tax return (can be a loss).
        public var profitClosedIntoPersonalTax: Double
        /// Capital the owner has put in so far (before the share capital), carried as contributed capital.
        public var contributedCapitalCarried: Double
        public var shareCount: Double
        public var shareNominal: Double
        public var ownerSharePercent: Double
        public var loans: [LoanLine]
        public var valueBefore: Double
        public var valueAfter: Double
        public var netWorthBefore: Double
        public var netWorthAfter: Double
        public var personalBalanceAfter: Double
        public var companyBalanceAfter: Double
        public var consequences: [String]
    }

    public enum Outcome: Equatable, Sendable {
        case ok
        case blocked(Block)
        case notEnoughCash
    }

    // MARK: Fee, capital, name

    /// The country's conversion fee (its own figure when the data has one, else the registration fee).
    public static func conversionFee(country: Country) -> Double { country.conversionFee > 0 ? jsRound(country.conversionFee) : country.registrationFee }

    /// The name with the legal ending of `form`: the ending of the other form is dropped, the right one added (from the country's own data).
    public static func name(_ name: String, form: LegalForm, country: Country) -> String {
        let forms = country.companyForms
        let limited = forms["limitedShort"] ?? "", sole = forms["soleTraderShort"] ?? ""
        var n = name.trimmingCharacters(in: .whitespaces)
        func strip(_ end: String) { if !end.isEmpty, n.hasSuffix(" " + end) { n = String(n.dropLast(end.count + 1)).trimmingCharacters(in: .whitespaces) } }
        switch form {
        case .limited:
            strip(sole)
            if !limited.isEmpty, !n.hasSuffix(" " + limited), n != limited { n += " " + limited }
        case .soleTrader:
            strip(limited)
        }
        return n
    }

    static func block(_ co: Company, country: Country?, state s: GameState) -> Block? {
        if co.form == .limited { return .alreadyLimited }
        if co.status != .open && co.status != .setup && co.status != .closed { return .notTrading }
        if !co.value("chain").isNull, Chains.chain(s, of: co) != nil { return .chainStore }
        if country == nil { return .unknownCountry }
        return nil
    }

    // MARK: Plan (a dry run on a copy)

    public static func plan(_ s: GameState, companyID: Int, payer: Payer = .personal, accountantID: Int? = nil, data: GameData, context: FinanceContext) -> Plan? {
        guard let co = s.company(companyID) else { return nil }
        let country = data.countries[co.countryCode]
        let fee = country.map { conversionFee(country: $0) } ?? 0
        let capital = country?.shareCapitalMinimum ?? 0
        let blocked = block(co, country: country, state: s)
        let forms = country?.companyForms ?? [:]
        let nameAfter = country.map { name(co.name, form: .limited, country: $0) } ?? co.name
        let liquid = Payments.liquid(s)
        func option(_ p: Payer) -> PayerOption {
            switch p {
            case .personal:
                let need = capital + fee
                return PayerOption(payer: .personal, accountName: "Your personal account", balance: s.cash, spendable: liquid, needed: need,
                                   affordable: liquid >= need, shortfall: max(0, need - liquid))
            case .company:
                // The company pays the fee only; the owner still pays the share capital personally.
                let ok = co.cash >= fee && liquid >= capital
                return PayerOption(payer: .company, accountName: co.name + " account", balance: co.cash, spendable: co.cash, needed: fee,
                                   affordable: ok, shortfall: max(0, fee - co.cash) + max(0, capital - liquid))
            }
        }
        let options = [option(.personal), option(.company)]
        let chosen = options.first { $0.payer == payer } ?? options[0]
        let ytd = (co.books.year["rev"] ?? 0) - Books.expenses(co.books.year)
        let contributed = max(0, co.ownerNetFlow)
        let loans = s.loans.filter { $0.companyID == companyID }.map { LoanLine(loanID: $0.id, name: $0.name, balance: $0.balance, personallyGuaranteed: true) }
        let acc = co.value("acc")
        var accName = acc["name"].string, accFee = acc["fee"].double
        if acc.isNull || accName.isEmpty {
            var tmp = s
            let pool = Providers.pool(for: co.countryCode, state: &tmp, countries: data.countries).accountants
            if let a = pool.first(where: { $0["id"].int == accountantID }) ?? (pool.count > 1 ? pool[1] : pool.first) { accName = a["name"].string; accFee = a["fee"].double }
        }
        // Dry run on a copy: the same code that will run, so the after-figures are the result, not a guess.
        var after = s
        var nwAfter = Valuation.netWorth(s, trades: data.catalog).total
        var valueAfter = Valuation.companyValue(co, state: s, trades: data.catalog)
        var personalAfter = s.cash, companyAfter = co.cash
        if blocked == nil, chosen.affordable {
            _ = execute(&after, companyID: companyID, payer: payer, accountantID: accountantID, data: data, context: context)
            nwAfter = Valuation.netWorth(after, trades: data.catalog).total
            if let c2 = after.company(companyID) { valueAfter = Valuation.companyValue(c2, state: after, trades: data.catalog); companyAfter = c2.cash }
            personalAfter = after.cash
        }
        let shareCount = shareTotal
        var lines: [String] = []
        lines.append("The business keeps its name, staff, contracts, equipment, stock and bank account; its legal form changes from \(forms["soleTrader"] ?? "sole trader") to \(forms["limited"] ?? "limited company").")
        lines.append("You pay the share capital personally; it goes into the company and is yours as the only shareholder.")
        lines.append("The fee is charged to \(chosen.accountName).")
        lines.append(ytd >= 0 ? "Profit so far this year stays on your personal tax return; the company's own tax year starts at the conversion."
                              : "The loss so far this year stays on your personal tax return; the company's own tax year starts at the conversion.")
        lines.append("Limited liability: from now the company's debts are the company's, but loans already signed keep your personal guarantee unless the bank agrees to release it.")
        lines.append("From now you can take money out only as salary or dividends; a sole trader's drawings stop.")
        lines.append("A limited company must have an accountant: \(accName.isEmpty ? "one is appointed" : accName + " keeps the books") for \(accFee > 0 ? "a monthly fee" : "a fee").")
        return Plan(companyID: companyID, companyName: co.name, blocked: blocked, fee: fee, shareCapital: capital, payer: payer, payerOptions: options,
                    affordable: chosen.affordable, accountToCharge: chosen.accountName,
                    currentFormName: forms["soleTrader"] ?? "Sole trader", newFormName: forms["limited"] ?? "Limited company",
                    nameBefore: co.name, nameAfter: nameAfter, accountantName: accName, accountantMonthlyFee: accFee, accountantRequired: true,
                    profitClosedIntoPersonalTax: ytd, contributedCapitalCarried: contributed, shareCount: shareCount,
                    shareNominal: shareCount > 0 ? capital / shareCount : 0, ownerSharePercent: co.ownership, loans: loans,
                    valueBefore: Valuation.companyValue(co, state: s, trades: data.catalog), valueAfter: valueAfter,
                    netWorthBefore: Valuation.netWorth(s, trades: data.catalog).total, netWorthAfter: nwAfter,
                    personalBalanceAfter: personalAfter, companyBalanceAfter: companyAfter, consequences: lines)
    }

    // MARK: The transaction

    public static func convert(_ s: inout GameState, companyID: Int, payer: Payer = .personal, accountantID: Int? = nil, data: GameData, context: FinanceContext) -> Outcome {
        guard let co = s.company(companyID) else { return .blocked(.notTrading) }
        if let b = block(co, country: data.countries[co.countryCode], state: s) { return .blocked(b) }
        return execute(&s, companyID: companyID, payer: payer, accountantID: accountantID, data: data, context: context)
    }

    @discardableResult
    static func execute(_ s: inout GameState, companyID: Int, payer: Payer, accountantID: Int?, data: GameData, context: FinanceContext) -> Outcome {
        guard let i = s.companyIndex(companyID), let country = data.countries[s.companies[i].countryCode] else { return .blocked(.unknownCountry) }
        let fee = conversionFee(country: country), capital = country.shareCapitalMinimum
        // Everything is checked before anything moves.
        switch payer {
        case .personal: if Payments.liquid(s) < fee + capital { return .notEnoughCash }
        case .company: if s.companies[i].cash < fee || Payments.liquid(s) < capital { return .notEnoughCash }
        }
        let name0 = s.companies[i].name
        if payer == .personal {
            Payments.transferFromSavings(&s, need: fee + capital)
            Payments.playerPays(&s, fee, label: "Conversion to a limited company: fee", companyID: companyID)
        } else {
            Payments.transferFromSavings(&s, need: capital)
            Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Conversion to a limited company: fee")
        }
        // Close the sole-trader part of the year into the owner's personal return (a loss reduces it); the corporate base opens at zero.
        let y = s.companies[i].books.year, m = s.companies[i].books.month
        let ytd = (y["rev"] ?? 0) - Books.expenses(y)
        s.tax.soleTraderFrozenProfit += ytd
        s.companies[i].set("convMonthProfit", .number((m["rev"] ?? 0) - Books.expenses(m)))
        // The owner pays the share capital personally.
        if capital > 0 {
            Payments.playerPays(&s, capital, label: "Share capital: \(name0)", companyID: companyID)
            Ledger.moveRaw(&s, .company(companyID), capital)
        }
        s.companies[i].ownerNetFlow += capital
        s.companies[i].shareCapital = capital
        s.companies[i].injectedCapital = max(capital, s.companies[i].ownerNetFlow)
        if capital > 0 { s.companies[i].addTransaction(week: s.week, amount: capital, label: "Share capital paid in") }
        s.companies[i].form = .limited
        s.companies[i].lossCarryAtYearStart = s.companies[i].lossCarryForward
        s.companies[i].yearProfitSoFar = 0
        s.companies[i].taxAccrued = 0
        // Legal identity.
        let newName = name(name0, form: .limited, country: country)
        s.companies[i].name = newName
        var legal = s.companies[i].value("legal")
        if legal.isNull { legal = .object([:]) }
        legal["form"] = "limited"
        legal["since"] = .number(Double(s.week))
        legal["name"] = .string(newName)
        legal["shares"] = .object(["count": .number(shareTotal), "nominal": .number(capital / shareTotal)])
        var hist = legal["hist"].array
        hist.append(.object(["w": .number(Double(s.week)), "from": "soleTrader", "to": "limited", "fee": .number(fee), "capital": .number(capital),
                             "payer": .string(payer.rawValue), "nameBefore": .string(name0), "ytd": .number(ytd)]))
        legal["hist"] = .array(hist)
        s.companies[i].set("legal", legal)
        // Accountant and agreement, as the legal form requires.
        if s.companies[i].value("acc").isNull || s.companies[i].value("acc")["id"].isNull {
            CompanySetup.chooseAccountant(&s, companyID: companyID, accountantID: accountantID, data: data)
        } else {
            var docs = s.companies[i].value("docs")
            if docs["accountant_agreement"].isNull { docs["accountant_agreement"] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week))]) }
            s.companies[i].set("docs", docs)
        }
        // The personal guarantee stays on every loan signed so far.
        for k in s.loans.indices where s.loans[k].companyID == companyID && !s.loans[k].isGuaranteed { s.loans[k].isGuaranteed = true }
        s.note("\(newName) is now a limited company.", tone: "good", companyID: companyID)
        return .ok
    }
}
