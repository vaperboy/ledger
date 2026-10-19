import Foundation
import GameCore

/// Business choices ("knobs"): concept, menu, staffing model ... Each option changes prices (t), demand (d),
/// capacity (k), costs (c, w), quality (q) and so on. Original: `knobFx`, `knobOpts` in engine/company/company.js.
public enum Knobs {
    /// The options that are switched on for a knob.
    public static func activeOptions(_ co: Company, _ knob: Knob) -> [KnobOption] {
        let selected = co.value("knob")[knob.id].int
        if knob.isMulti {
            return knob.options.enumerated().filter { selected & (1 << $0.offset) != 0 }.map { $0.element }
        }
        return knob.options.indices.contains(selected) ? [knob.options[selected]] : []
    }

    public static func documentOK(_ co: Company, _ id: String) -> Bool {
        co.value("docs")[id]["st"].string == "ok"
    }

    /// Combined effect of the company's choices on one measure. `sum` adds the effects, otherwise they multiply.
    /// For customer demand ("d") the pull of an option drifts with the seasons. Original: `knobFx` + the
    /// 'business choices: their pull on customers drifts with the season' step.
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
