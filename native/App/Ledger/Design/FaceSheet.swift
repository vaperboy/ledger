import SwiftUI
import CoreGraphics
import ImageIO
import Employees

/// The owner's two sheets of face portraits (`Resources/faces-sheet.jpg`, 15 x 9 casual, and `Resources/faces-suits.jpg`, 13 x 13 business dress),
/// sliced at runtime into square portraits. The engine decides who gets which portrait (`FaceBook`, saved with the game); this only cuts the
/// picture for a `FaceKey` out of its sheet: a centred square of the cell, cached, safe to call from any thread. Faces are for employees only.
enum FaceSheet {
    private static let lock = NSLock()
    private static var sheets: [FaceSheetID: CGImage] = [:]
    private static var missing: Set<FaceSheetID> = []
    private static var images: [FaceKey: CGImage] = [:]

    private static func fileName(_ sheet: FaceSheetID) -> String { sheet == .casual ? "faces-sheet" : "faces-suits" }

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

    /// The crop rectangle of a cell: the centred square of the cell (cells may be wider than tall), a little inside the border; closer and shifted
    /// slightly for the zoomed variants.
    static func cropRect(sheet: FaceSheetID, cell: Int, variant: Int, sheetWidth: Int, sheetHeight: Int) -> CGRect {
        let cw = Double(sheetWidth) / Double(sheet.columns), ch = Double(sheetHeight) / Double(sheet.rows)
        let col = Double(cell % sheet.columns), row = Double(cell / sheet.columns)
        let zoomed = variant == 2 || variant == 3
        let side = min(cw, ch) * (zoomed ? 0.80 : 0.94)
        let cx = (col + 0.5) * cw + (zoomed ? cw * 0.02 : 0)
        let cy = (row + 0.5) * ch - (zoomed ? ch * 0.03 : 0)
        return CGRect(x: (cx - side / 2).rounded(), y: (cy - side / 2).rounded(), width: side.rounded(), height: side.rounded())
    }

    private static func render(_ key: FaceKey, from sheet: CGImage) -> CGImage? {
        let rect = cropRect(sheet: key.sheet, cell: key.cell, variant: key.variant, sheetWidth: sheet.width, sheetHeight: sheet.height)
        guard let cropped = sheet.cropping(to: rect) else { return nil }
        let size = cropped.width
        guard size > 0, let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cropped }
        let mirrored = key.variant == 1 || key.variant == 3
        if mirrored { ctx.translateBy(x: CGFloat(size), y: 0); ctx.scaleBy(x: -1, y: 1) }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
        if key.variant == 3 {
            // A mild warm grade over the whole picture, background included; faces stay natural.
            ctx.setBlendMode(.softLight)
            ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.78, blue: 0.55, alpha: 0.22))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        return ctx.makeImage() ?? cropped
    }
}
