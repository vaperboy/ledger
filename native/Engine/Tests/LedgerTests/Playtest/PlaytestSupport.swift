import XCTest
import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import SaveSystem

enum PT {
    static let env = ProcessInfo.processInfo.environment
    static var enabled: Bool { env["LEDGER_PLAYTEST"] == "1" }
    static var outDir: String {
        let d = env["LEDGER_PT_OUT"] ?? "/tmp/claude-0/s/playtest"
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    static var shard: (Int, Int) {
        let p = (env["LEDGER_PT_SHARD"] ?? "0/1").split(separator: "/").compactMap { Int($0) }
        return p.count == 2 && p[1] > 0 ? (p[0], p[1]) : (0, 1)
    }
    static func list(_ key: String, _ def: [String]) -> [String] { env[key].map { $0.split(separator: ",").map(String.init) } ?? def }
    static func ints(_ key: String, _ def: [Int]) -> [Int] { env[key].map { $0.split(separator: ",").compactMap { Int($0) } } ?? def }
    static var years: Int { Int(env["LEDGER_PT_YEARS"] ?? "3") ?? 3 }
    static var tag: String { env["LEDGER_PT_TAG"] ?? "run" }
}

final class Findings: @unchecked Sendable {
    static let shared = Findings()
    struct F { var sev: Int; var key: String; var title: String; var count: Int; var repro: String; var file: String; var detail: String }
    private let lock = NSLock()
    private var items: [String: F] = [:]
    private(set) var titleCounts: [String: Int] = [:]
    private(set) var runLines: [String] = []

    func add(_ sev: Int, _ key: String, _ title: String, repro: String, file: String, detail: String = "") {
        lock.lock(); defer { lock.unlock() }
        if var f = items[key] { f.count += 1; f.sev = min(f.sev, sev); items[key] = f }
        else { items[key] = F(sev: sev, key: key, title: title, count: 1, repro: repro, file: file, detail: detail) }
    }
    func countTitle(_ t: String, _ n: Int = 1) { lock.lock(); titleCounts[t, default: 0] += n; lock.unlock() }
    func runLine(_ s: String) { lock.lock(); runLines.append(s); lock.unlock() }
    var all: [F] { lock.lock(); defer { lock.unlock() }; return items.values.sorted { ($0.sev, -$0.count, $0.key) < ($1.sev, -$1.count, $1.key) } }

    func flush(tag: String = PT.tag) {
        lock.lock(); defer { lock.unlock() }
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
        var out = ""
        for f in items.values { out += "\(f.sev)\t\(clean(f.key))\t\(f.count)\t\(clean(f.title))\t\(clean(f.repro))\t\(clean(f.file))\t\(clean(f.detail))\n" }
        append(out, to: "findings-\(tag).tsv")
        append(titleCounts.map { "\($0.value)\t\(clean($0.key))\n" }.joined(), to: "titles-\(tag).tsv")
        append(runLines.map { $0 + "\n" }.joined(), to: "runs-\(tag).tsv")
        items = [:]; titleCounts = [:]; runLines = []
    }
    private func append(_ s: String, to name: String) {
        guard !s.isEmpty else { return }
        let path = PT.outDir + "/" + name
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); try? h.close() }
        else { try? s.write(toFile: path, atomically: true, encoding: .utf8) }
    }
}

enum Progress {
    static func start(_ job: String) { line("START \(job)") }
    static func done(_ job: String) { line("DONE \(job)") }
    private static let lock = NSLock()
    static func line(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        let path = PT.outDir + "/progress-\(PT.tag)-\(PT.shard.0).log"
        let d = (s + "\n").data(using: .utf8)!
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: URL(fileURLWithPath: path)) }
    }
    static var skip: Set<String> {
        guard let p = PT.env["LEDGER_PT_SKIPFILE"], let t = try? String(contentsOfFile: p, encoding: .utf8) else { return [] }
        return Set(t.split(separator: "\n").map(String.init))
    }
}

func fnv(_ data: Data) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in data { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return h
}

extension GameEngine {
    var playtestHash: String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        guard let d = try? enc.encode(state) else { return "unencodable" }
        return String(fnv(d), radix: 16)
    }
}

func badNumber(_ v: JSONValue, _ path: String = "") -> String? {
    switch v {
    case .number(let d): return d.isFinite ? nil : path
    case .array(let a): for (i, x) in a.enumerated() { if let p = badNumber(x, "\(path)[\(i)]") { return p } }; return nil
    case .object(let o): for k in o.keys.sorted() { if let p = badNumber(o[k]!, path + "." + k) { return p } }; return nil
    default: return nil
    }
}

func normTitle(_ s: String, names: [String]) -> String {
    var t = s
    for n in names where n.count > 2 { t = t.replacingOccurrences(of: n, with: "{co}") }
    var out = ""
    var lastHash = false
    for ch in t.lowercased() {
        if ch.isNumber { if !lastHash { out.append("#") }; lastHash = true } else { out.append(ch); lastHash = false }
    }
    return String(out.prefix(70))
}
