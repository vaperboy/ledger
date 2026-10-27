import SwiftUI
import CoreGraphics
import ImageIO
import Employees

/// One portrait picked for a person: a cell of the sheet and a variant of it (0 is the original, 1 mirrored, 2 a closer offset crop,
/// 3 mirrored and closer with a mild warm grade).
struct FaceChoice: Hashable {
    var cell: Int
    var variant: Int
}

/// The owner's sheet of 135 face portraits (`Resources/faces-sheet.jpg`, 15 columns x 9 rows), sliced at runtime into square portraits.
/// Faces are for employees only (managers, assistants, staff, candidates). `face(for:)` is the pure, deterministic choice;
/// `choice(for:group:)` adds a per-group registry so two people of one company do not share a cell and variant while that can be avoided.
enum FaceSheet {
    static let columns = 15
    static let rows = 9
    static let variantCount = 4

    /// gender (F/M), age band (Y/M/O), region (S E U A L W) per cell, row by row, left to right.
    private static let tagRows: [String] = [
        "FYS FYE FYS FYS MYS MYE MYU FYE FMS MOE FOU MOU MYA MYU MOU",
        "FYE FYS MYS FYU MYS MYU MYS MML FYS MYS FYE MOU FYA MYS MYA",
        "FYS FYS FYE MYW MOU FYS MYA FMS MYS MYA MMU MMU FYS MYA MYA",
        "FMS FYE FYE MMS FYE FYE MYS MYA FYE FYE MMS FYE FMU MYS MOU",
        "FYE MOU FYS MYS MYS MYS MYS FYL FYS MMU FMS FYE MYS MME MYA",
        "MYE FYU MOU MMA FYS FYS FYS MME FYS MME MYS MYS MYS FMS MOU",
        "FYS MYS FYE FYE MOA MYA MYE MMA MMU MYS MYE FYA FYE MYA FYE",
        "FYS FYE FYS MYS FYS MYA MYS MYS FMS MME MYA MMU FYE MOA MME",
        "FYS MOU MMA MYU FYE MMS MYA FYE MYE MOU FMS FYE FYS MYS MYE",
    ]

    struct Tag { var gender: Character; var age: Character; var region: Character }

    /// 135 tags in cell order (index = row * 15 + column).
    static let tags: [Tag] = tagRows.flatMap { row in
        row.split(separator: " ").map { t -> Tag in
            let c = Array(t)
            return Tag(gender: c[0], age: c[1], region: c[2])
        }
    }

    // MARK: Assignment (pure)

    /// FNV-1a, so the choice does not depend on Swift's per-launch randomised hashing.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    /// Cells in preference order: gender + age + region, gender + region, gender + age, gender, any. An unknown region skips the region tiers.
    static func tiers(_ t: FaceTraits) -> [[Int]] {
        let all = Array(0..<tags.count)
        let g = all.filter { tags[$0].gender == t.gender }
        var out: [[Int]] = []
        if let r = t.region {
            out.append(g.filter { tags[$0].age == t.ageBand && tags[$0].region == r })
            out.append(g.filter { tags[$0].region == r })
        }
        out.append(g.filter { tags[$0].age == t.ageBand })
        out.append(g)
        out.append(all)
        return out.filter { !$0.isEmpty }
    }

    /// The portrait for a person: stable for the same traits and salt; avoids the cell+variant pairs in `used` while an unused one exists
    /// in the best tier that has any (then in the next tier). `salt` (for example a company id) spreads people of one company apart.
    static func face(for traits: FaceTraits, used: Set<FaceChoice> = [], salt: String = "") -> FaceChoice {
        let h = stableHash(traits.key + "|" + salt)
        let tierList = tiers(traits)
        for cells in tierList {
            let start = Int(h % UInt64(cells.count))
            let vStart = Int((h >> 17) % UInt64(variantCount))
            // Original looks first for every cell, then the variants: distinct cells before repeated cells.
            let order: [Int] = [0] + (1..<variantCount).map { 1 + ($0 - 1 + vStart) % (variantCount - 1) }
            for variant in order {
                for k in 0..<cells.count {
                    let c = FaceChoice(cell: cells[(start + k) % cells.count], variant: variant)
                    if !used.contains(c) { return c }
                }
            }
        }
        let cells = tierList[0]
        return FaceChoice(cell: cells[Int(h % UInt64(cells.count))], variant: 0)
    }

    // MARK: Registry (stable within a session, no two of one group alike)

    private static let lock = NSLock()
    private static var assigned: [String: FaceChoice] = [:]
    private static var usedByGroup: [String: Set<FaceChoice>] = [:]

    /// The portrait of a person inside a group (a company id, or "" for none). The first answer is remembered, so it does not change
    /// while the app runs, and later people of the group get a different cell and variant where one is free.
    static func choice(for traits: FaceTraits, group: String) -> FaceChoice {
        lock.lock(); defer { lock.unlock() }
        let slot = group + "#" + traits.key
        if let c = assigned[slot] { return c }
        let c = face(for: traits, used: usedByGroup[group] ?? [], salt: group)
        assigned[slot] = c
        usedByGroup[group, default: []].insert(c)
        return c
    }

    // MARK: Slicing (cached, thread safe)

    private static var sheet: CGImage?
    private static var sheetTried = false
    private static var images: [FaceChoice: CGImage] = [:]

    private static func loadSheet() -> CGImage? {
        if sheetTried { return sheet }
        sheetTried = true
        if let url = Bundle.main.url(forResource: "faces-sheet", withExtension: "jpg"),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            sheet = CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        return sheet
    }

    /// The square portrait for a choice, or nil when the sheet is missing (callers keep the initials or icon).
    static func image(_ choice: FaceChoice) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let cached = images[choice] { return cached }
        guard choice.cell >= 0, choice.cell < columns * rows, let sheet = loadSheet(), let img = render(choice, from: sheet) else { return nil }
        images[choice] = img
        return img
    }

    /// The crop rectangle of a cell: the centred square of the cell (cells are wider than tall), a little inside the border, closer for
    /// the zoomed variants and shifted slightly so the crop differs.
    static func cropRect(cell: Int, variant: Int, sheetWidth: Int, sheetHeight: Int) -> CGRect {
        let cw = Double(sheetWidth) / Double(columns), ch = Double(sheetHeight) / Double(rows)
        let col = Double(cell % columns), row = Double(cell / columns)
        let zoomed = variant == 2 || variant == 3
        let side = min(cw, ch) * (zoomed ? 0.80 : 0.94)
        let cx = (col + 0.5) * cw + (zoomed ? cw * 0.02 : 0)
        let cy = (row + 0.5) * ch - (zoomed ? ch * 0.03 : 0)
        return CGRect(x: (cx - side / 2).rounded(), y: (cy - side / 2).rounded(), width: side.rounded(), height: side.rounded())
    }

    private static func render(_ choice: FaceChoice, from sheet: CGImage) -> CGImage? {
        let rect = cropRect(cell: choice.cell, variant: choice.variant, sheetWidth: sheet.width, sheetHeight: sheet.height)
        guard let cropped = sheet.cropping(to: rect) else { return nil }
        let size = cropped.width
        guard size > 0, let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cropped }
        let mirrored = choice.variant == 1 || choice.variant == 3
        if mirrored { ctx.translateBy(x: CGFloat(size), y: 0); ctx.scaleBy(x: -1, y: 1) }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
        if choice.variant == 3 {
            // A mild warm grade over the whole picture, background included; faces stay natural.
            ctx.setBlendMode(.softLight)
            ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.78, blue: 0.55, alpha: 0.22))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        return ctx.makeImage() ?? cropped
    }
}
