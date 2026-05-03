import CoreGraphics

extension MediaExport {
    static func even(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }
}
