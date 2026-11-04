import Foundation

/// Which trades use real per-item records (`ItemModels`), one registry per rollout wave, each in its own file
/// (`ItemWave1.swift` ... `ItemWave11.swift`) so waves never edit the same lines. A trade appears in exactly one wave.
public enum ItemWaves {
    public static var all: Set<String> {
        w1.union(w2).union(w3).union(w4).union(w5).union(w6).union(w7).union(w8).union(w9).union(w10).union(w11)
    }
}
