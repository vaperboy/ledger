import SwiftUI
import CoreGraphics
import ImageIO
import Employees

/// The owner's four sheets of face portraits (`Resources/faces-sheet.jpg`, 15 x 9 casual; `Resources/faces-suits.jpg`, 13 x 13 business dress;
/// `Resources/art/workers-sheet.jpg`, 90 casual faces in an uneven grid; `Resources/art/managers-sheet.jpg`, 110 faces in business wear),
/// sliced at runtime into square portraits. The engine decides who gets which portrait (`FaceBook`, saved with the game); this only cuts the
/// picture for a `FaceKey` out of its sheet: a centred square of the cell, cached, safe to call from any thread. Faces are for employees only.
enum FaceSheet {
    private static let lock = NSLock()
    private static var sheets: [FaceSheetID: CGImage] = [:]
    private static var missing: Set<FaceSheetID> = []
    private static var images: [FaceKey: CGImage] = [:]

    private static func fileName(_ sheet: FaceSheetID) -> String {
        switch sheet {
        case .casual: return "faces-sheet"
        case .suits: return "faces-suits"
        case .workers: return "workers-sheet"
        case .managers: return "managers-sheet"
        }
    }

    // MARK: Cell rectangles of the two uneven sheets, found by pixel analysis of the 1696 x 2528 originals (the printed numbers are unreliable).

    /// Workers: row 1 has 10 cells (about 160 px pitch), the 10 rows below have 8 (about 200 px pitch).
    private static let workerRowBands: [(Int, Int)] = [(184, 409), (414, 622), (628, 836), (842, 1049), (1054, 1260), (1266, 1469), (1475, 1678), (1684, 1887), (1892, 2095), (2101, 2303), (2309, 2512)]
    private static let workerCols10: [(Int, Int)] = [(68, 224), (230, 383), (389, 543), (549, 703), (706, 863), (868, 1024), (1029, 1182), (1188, 1344), (1349, 1503), (1509, 1667)]
    private static let workerCols8: [(Int, Int)] = [(68, 261), (267, 462), (468, 663), (668, 863), (869, 1064), (1070, 1265), (1270, 1466), (1471, 1667)]
    /// Managers: 11 rows x 10 columns of portrait-shaped cells.
    private static let managerRowBands: [(Int, Int)] = [(154, 371), (379, 603), (610, 834), (841, 1051), (1057, 1261), (1267, 1468), (1474, 1673), (1679, 1878), (1884, 2083), (2090, 2288), (2295, 2492)]
    private static let managerCols: [(Int, Int)] = [(62, 214), (224, 373), (383, 532), (542, 691), (701, 850), (860, 1009), (1019, 1168), (1178, 1327), (1337, 1486), (1496, 1648)]

    /// The cell rectangle in the 1696 x 2528 reference size, and whether the cell is much taller than wide (the face sits in its upper part).
    private static func irregularCell(_ sheet: FaceSheetID, _ cell: Int) -> CGRect? {
        if sheet == .workers {
            if cell < 10 { let c = workerCols10[cell], r = workerRowBands[0]; return CGRect(x: c.0, y: r.0, width: c.1 - c.0 + 1, height: r.1 - r.0 + 1) }
            let k = cell - 10
            guard k < 80 else { return nil }
            let c = workerCols8[k % 8], r = workerRowBands[1 + k / 8]
            return CGRect(x: c.0, y: r.0, width: c.1 - c.0 + 1, height: r.1 - r.0 + 1)
        }
        guard cell < 110 else { return nil }
        let c = managerCols[cell % 10], r = managerRowBands[cell / 10]
        return CGRect(x: c.0, y: r.0, width: c.1 - c.0 + 1, height: r.1 - r.0 + 1)
    }

    private static func loadSheet(_ sheet: FaceSheetID) -> CGImage? {
        if let img = sheets[sheet] { return img }
        if missing.contains(sheet) { return nil }
        if let url = Bundle.main.url(forResource: fileName(sheet), withExtension: "jpg"),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            sheets[sheet] = img
            return img
        }
        missing.insert(sheet)
        return nil
    }

    /// The portrait for a key, or nil when the key is nil or its sheet cannot be loaded (callers keep the initials or icon).
    static func image(_ key: FaceKey?) -> CGImage? {
        guard let key else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let cached = images[key] { return cached }
        guard key.cell >= 0, key.cell < key.sheet.cellCount, let sheet = loadSheet(key.sheet), let img = render(key, from: sheet) else { return nil }
        images[key] = img
        return img
    }

    static func image(_ text: String?) -> CGImage? { image(FaceKey(text)) }

    /// The crop rectangle of a cell: a square inside the cell (the faces of the uneven sheets sit in the upper part of a taller cell, so the square
    /// leans up), a little inside the border.
    static func cropRect(sheet: FaceSheetID, cell: Int, sheetWidth: Int, sheetHeight: Int) -> CGRect {
        var box: CGRect
        var lean = 0.0
        switch sheet {
        case .casual, .suits:
            let cols = sheet == .casual ? 15 : 13, rows = sheet == .casual ? 9 : 13
            let cw = Double(sheetWidth) / Double(cols), ch = Double(sheetHeight) / Double(rows)
            box = CGRect(x: Double(cell % cols) * cw, y: Double(cell / cols) * ch, width: cw, height: ch)
        case .workers, .managers:
            let k = Double(sheetWidth) / 1696
            guard let r = irregularCell(sheet, cell) else { return .zero }
            box = CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k)
            lean = sheet == .managers ? 0.25 : 0.1
        }
        let side = min(box.width, box.height) * 0.94
        let slack = box.height - side
        let cx = box.midX
        let cy = box.minY + side / 2 + slack * (0.5 - lean)
        return CGRect(x: (cx - side / 2).rounded(), y: (cy - side / 2).rounded(), width: side.rounded(), height: side.rounded())
    }

    private static func render(_ key: FaceKey, from sheet: CGImage) -> CGImage? {
        let rect = cropRect(sheet: key.sheet, cell: key.cell, sheetWidth: sheet.width, sheetHeight: sheet.height)
        return sheet.cropping(to: rect)
    }
}
