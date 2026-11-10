import Foundation
import GameCore

public struct FaceTraits: Equatable, Hashable, Sendable {
    public var key: String
    public var gender: Character
    public var ageBand: Character
    public var region: Character?

    public init(key: String, gender: Character, ageBand: Character, region: Character?) {
        self.key = key; self.gender = gender; self.ageBand = ageBand; self.region = region
    }

    public static func of(_ p: Person, countryCode: String?) -> FaceTraits {
        of(id: p.id, name: p.name, age: p.age, countryCode: countryCode)
    }

    public static func of(id: Int, name: String, age: Int, countryCode: String?) -> FaceTraits {
        let region: Character? = countryCode.flatMap { Self.region(countryCode: $0) }
        return FaceTraits(key: "p\(id)-\(name)", gender: gender(firstName: firstName(name), seed: id), ageBand: ageBand(age), region: region)
    }

    public static func named(_ name: String, countryCode: String?) -> FaceTraits {
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
        return of(id: seed, name: name, age: 45, countryCode: countryCode)
    }

    public static func ageBand(_ age: Int) -> Character { age < 35 ? "Y" : age < 55 ? "M" : "O" }

    static func firstName(_ full: String) -> String {
        let s = full.trimmingCharacters(in: .whitespaces)
        return s.split(separator: " ").first.map(String.init) ?? s
    }

    static let femaleNames: Set<String> = [
        "Agnieszka", "Agnė", "Aino", "Aisha", "Alice", "Alma", "Amanda", "Amelia", "Ana", "Anjali", "Anke", "Anna", "Anouk", "Aoife", "Aurora",
        "Austėja", "Ava", "Beatrice", "Beatriz", "Camila", "Camilla", "Carmen", "Charlotte", "Chiara", "Chloe", "Chloé", "Ciara", "Clara",
        "Daniela", "Eevi", "Eglė", "Elena", "Elin", "Elise", "Ella", "Ellie", "Emi", "Emily", "Emma", "Eun-ji", "Eunji", "Eva", "Ewa",
        "Fatima", "Fernanda", "Fiadh", "Fiona", "Francesca", "Freja", "Frida", "Georgia", "Giedrė", "Ginevra", "Gintarė", "Giulia", "Grace",
        "Guadalupe", "Ha-eun", "Haeun", "Hanna", "Hannah", "Hanne", "Helena", "Helmi", "Hessa", "Hina", "Ida", "Ieva", "Indrė", "Ingrid",
        "Inès", "Iris", "Isabel", "Isabella", "Isabelle", "Isla", "Jennifer", "Jessica", "Joanna", "Johanna", "Josefin", "Julia", "Juliana",
        "Julie", "Jurgita", "Júlia", "Kaisa", "Karin", "Karla", "Karolina", "Katarzyna", "Katharina", "Kavya", "Kristina", "Larissa", "Laura",
        "Lauren", "Layla", "Lea", "Lena", "Lene", "Linda", "Lina", "Linn", "Linnea", "Lise", "Live", "Lotte", "Louise", "Lucy", "Lucía", "Léa",
        "Magdalena", "Maja", "Manon", "Manuela", "Maria", "Mariam", "Mariana", "Marie", "Marloes", "Marta", "Marte", "Martina", "Mary",
        "María", "Małgorzata", "Megan", "Mei", "Mette", "Mia", "Milda", "Min-seo", "Minseo", "Moa", "Monika", "Nana",
        "Nanami", "Natalia", "Niamh", "Nina", "Noor", "Noora", "Nora", "Noura", "Nur", "Nuria", "Olivia", "Ona", "Paola", "Paula",
        "Poppy", "Priya", "Rachel", "Randi", "Regina", "Riikka", "Róisín", "Rūta", "Ruby", "Sakura", "Sanna", "Sanne", "Sara", "Sarah",
        "Seo-yeon", "Seoyeon", "Shamma", "Shi", "Silje", "Siobhán", "Siti", "Sofia", "Sofie", "Sofía", "Soo-ah", "Sophia", "Sophie",
        "Soyeon", "Tess", "Thea", "Valentina", "Valeria", "Venla", "Vilde", "Weronika", "Ximena", "Xin", "Yui", "Yuna", "Zoe", "Zofia", "Élise",
    ]
    static let unisexNames: Set<String> = [
        "Andrea", "Aoi", "Camille", "Charlie", "Chris", "Jesse", "Kai", "Max", "Nico", "Rin", "Ren", "Ola", "Kari", "Jules", "Hyun", "Joon",
        "Jiho", "Ji-woo", "Jiwoo", "Cooper", "Logan", "Ashley", "Hunter", "Mason", "Jayden", "Tyler",
    ]

    public static func gender(firstName: String, seed: Int) -> Character {
        if femaleNames.contains(firstName) { return "F" }
        if unisexNames.contains(firstName) { return abs(seed % 1000) % 2 == 0 ? "F" : "M" }
        return "M"
    }

    static let regionByCountry: [String: Character] = {
        var m: [String: Character] = [:]
        for c in "GB UK IE DE FR NO SE PL LT ES NL CH IT DK FI AT BE PT CZ US CA AU NZ".split(separator: " ") { m[String(c)] = "U" }
        for c in "IN PK BD LK NP".split(separator: " ") { m[String(c)] = "S" }
        for c in "CN JP KR VN TH PH SG MY ID TW HK".split(separator: " ") { m[String(c)] = "E" }
        for c in "NG GH KE ZA ET TZ".split(separator: " ") { m[String(c)] = "A" }
        for c in "BR MX CO AR CL PE".split(separator: " ") { m[String(c)] = "L" }
        for c in "TR EG SA AE IR IQ QA KW JO".split(separator: " ") { m[String(c)] = "W" }
        return m
    }()

    public static func region(countryCode: String) -> Character? { regionByCountry[countryCode.uppercased()] }
}
