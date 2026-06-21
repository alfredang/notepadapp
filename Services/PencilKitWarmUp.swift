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

        // A 1×1, invisible, non-interactive canvas — enough to initialize the
        // engine without ever being seen or stealing touches.
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        canvas.alpha = 0
        canvas.isUserInteractionEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 1)
        window.addSubview(canvas)
        canvas.layoutIfNeeded()
        // Force a render pass, then drop the throwaway canvas.
        _ = canvas.drawing.dataRepresentation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            canvas.removeFromSuperview()
        }
    }
}
