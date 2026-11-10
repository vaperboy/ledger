import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct DocumentForm: Equatable, Sendable {
    public var id: String
    public var name: String
    public var issuer: String
    public var note: String
    public var fee: Double
    public var weeks: Int
    public var status: String
    public var answerWeek: Int?
}

public struct LicenceLine: Equatable, Identifiable, Sendable {
    public var id: String
    public var form: DocumentForm
    public var unlocks: [String]
}

public extension GameEngine {
    func documentForm(companyID: Int, documentID: String) -> DocumentForm? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return nil }
        let w = World(state: state, data: data)
        guard let dd = Documents.definition(documentID, country: w.country(co), tables: data.catalog.tables) else { return nil }
        let d = co.value("docs")[documentID]
        return DocumentForm(id: documentID, name: dd.name, issuer: dd.issuer, note: dd.note, fee: Documents.cost(documentID, company: co, bd, w),
                            weeks: Documents.waitWeeks(documentID, definition: dd, company: co, w), status: d["st"].string, answerWeek: d["done"].isNull ? nil : d["done"].int)
    }

    mutating func applyForDocument(companyID: Int, documentID: String) -> Documents.ApplyResult {
        var r = Documents.ApplyResult.alreadyHeld
        update { s, d, _ in r = Documents.applySigned(documentID, companyID: companyID, state: &s, data: d) }
        return r
    }

    func licences(companyID: Int) -> [LicenceLine] {
        guard let co = state.company(companyID), co.status == .open, let bd = data.catalog[co.type] else { return [] }
        var byDoc: [String: [String]] = [:]
        for knob in bd.knobs { for o in knob.options { for id in o.requiredDocs { byDoc[id, default: []].append(o.name) } } }
        return byDoc.keys.sorted().compactMap { id -> LicenceLine? in
            guard let f = documentForm(companyID: companyID, documentID: id) else { return nil }
            return LicenceLine(id: id, form: f, unlocks: byDoc[id] ?? [])
        }
    }
}
