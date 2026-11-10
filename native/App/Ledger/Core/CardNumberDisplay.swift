import Foundation

enum CardNumberDisplay {
    static func digits16(_ raw: String, companyID: Int) -> String {
        var out: [Character] = []
        for c in raw where c.isASCII && c.isNumber {
            if out.count < 16 { out.append(c) }
        }
        var x: UInt64 = UInt64(truncatingIfNeeded: companyID) &* 2_654_435_761 &+ 40_503
        while out.count < 16 {
            x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let d: UInt64 = (x >> 33) % 10
            out.append(Character(String(d)))
        }
        return String(out)
    }

    static func masked(_ raw: String, companyID: Int) -> String {
        let d: String = digits16(raw, companyID: companyID)
        return "**** **** **** " + String(d.suffix(4))
    }
}
