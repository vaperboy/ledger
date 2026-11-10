import Foundation
import GameCore

public enum Knobs {
    public static func activeOptions(_ co: Company, _ knob: Knob) -> [KnobOption] {
        let selected = co.value("knob")[knob.id].int
        if knob.isMulti {
            return knob.options.enumerated().filter { selected & (1 << $0.offset) != 0 }.map { $0.element }
        }
        return knob.options.indices.contains(selected) ? [knob.options[selected]] : []
    }

    public static func mask(_ mask: Int, option: Int, on: Bool) -> Int {
        guard option >= 0, option < 62 else { return mask }
        return on ? mask | (1 << option) : mask & ~(1 << option)
    }

    public static func documentOK(_ co: Company, _ id: String) -> Bool {
        co.value("docs")[id]["st"].string == "ok"
    }

    public static func effect(_ co: Company, _ bd: Trade, _ key: String, _ w: World, sum: Bool = false) -> Double {
        var v: Double = sum ? 0 : 1
        for knob in bd.knobs {
            for o in activeOptions(co, knob) {
                if !o.requiredDocs.allSatisfy({ documentOK(co, $0) }) { continue }
                if let x = o.effects[key] { v = sum ? v + x : v * x }
            }
        }
        if key == "d" && !sum && v != 1 {
            let m = clamp(1 + 0.4 * SeededNoise.wave(seed: w.state.seed, key: "kn\(co.id)", week: w.week)
                          + 0.4 * (SeededNoise.smooth(seed: w.state.seed, key: "kn\(co.id)", week: w.week, span: 8) - 0.5), 0.25, 1.6)
            v = 1 + (v - 1) * m
        }
        return v
    }
}
