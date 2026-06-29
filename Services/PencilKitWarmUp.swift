import UIKit
import PencilKit

/// Warms up PencilKit's drawing engine once per app launch.
///
/// The very first `PKCanvasView` in a process pays a one-time cost to spin up
/// PencilKit's rendering pipeline, which shows up as a noticeable lag before the
/// first stroke registers on a freshly opened notebook. Creating a throwaway
/// canvas off-screen at launch pays that cost up front, so the user's first real
/// page is responsive immediately.
@MainActor
enum PencilKitWarmUp {
    private static var warmed = false

    static func warmUp() {
        guard !warmed else { return }
        warmed = true

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else {
            warmed = false   // retry on the next opportunity once a window exists
            return
        }

        // A small, invisible, non-interactive canvas — large enough for the
        // renderer to initialize at a realistic scale, but never seen or able to
        // steal touches.
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 256, height: 256))
        canvas.alpha = 0
        canvas.isUserInteractionEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)

        // Push a real stroke through the pipeline. Rendering actual ink — not an
        // empty drawing — is what compiles PencilKit's Metal stroke shaders, the
        // true source of the lag before the *first* stroke on a fresh notebook.
        canvas.drawing = Self.warmUpDrawing()

        window.addSubview(canvas)
        canvas.layoutIfNeeded()
        // Force a render pass, then drop the throwaway canvas.
        _ = canvas.drawing.dataRepresentation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            canvas.removeFromSuperview()
        }
    }

    /// A one-stroke drawing used purely to exercise the ink renderer at launch.
    private static func warmUpDrawing() -> PKDrawing {
        let points = (0...16).map { i -> PKStrokePoint in
            let t = CGFloat(i)
            return PKStrokePoint(
                location: CGPoint(x: 20 + t * 12, y: 128 + sin(t / 2) * 40),
                timeOffset: TimeInterval(i) * 0.01,
                size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 0))
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
        return PKDrawing(strokes: [stroke])
    }
}
