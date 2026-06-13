import PencilKit
import UIKit

/// Remaps ink/shape colors so existing content stays visible when the page
/// template flips between white paper and a dark blackboard.
enum InkRecolor {
    static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// For the blackboard: turn near-black ink into white chalk (leave colors).
    static func forBlackboard(_ color: UIColor) -> UIColor {
        luminance(color) < 0.35 ? .white : color
    }

    /// For white paper: turn near-white ink back into black (leave colors).
    static func forWhitePaper(_ color: UIColor) -> UIColor {
        luminance(color) > 0.75 ? .black : color
    }

    /// Recolors every stroke in a serialized `PKDrawing`.
    static func recolorDrawing(_ data: Data, using map: (UIColor) -> UIColor) -> Data {
        guard !data.isEmpty, let drawing = try? PKDrawing(data: data) else { return data }
        let strokes = drawing.strokes.map { stroke -> PKStroke in
            PKStroke(ink: PKInk(stroke.ink.inkType, color: map(stroke.ink.color)),
                     path: stroke.path, transform: stroke.transform, mask: stroke.mask)
        }
        return PKDrawing(strokes: strokes).dataRepresentation()
    }
}
