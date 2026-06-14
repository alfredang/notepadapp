import PencilKit
import UIKit

/// The outcome of classifying a freehand stroke into a clean vector primitive.
/// Geometry is in page coordinates, matching `CanvasItem`.
enum RecognizedShape: Equatable {
    /// A closed shape (rectangle / circle / triangle / diamond) filling `frame`.
    case shape(ShapeKind, CGRect)
    /// A straight open stroke between two endpoints.
    case line(CGPoint, CGPoint)
    /// A straight open stroke with an arrowhead at `tip`.
    case arrow(from: CGPoint, tip: CGPoint)
}

/// Classifies a handwritten `PKStroke` into one of a small set of clean vector
/// shapes (line, arrow, rectangle, circle/ellipse, triangle, diamond) so the
/// editor can swap a wobbly sketch for a crisp `CanvasItem`. Recognition is only
/// ever run for a deliberate gesture (the hold-still at the end of a stroke), so
/// the heuristics favor a confident guess over rejecting borderline input.
@MainActor
enum ShapeRecognizer {
    /// Classifies the most recent stroke of `drawing`, or nil if it doesn't look
    /// like any supported shape (leave it as handwriting).
    static func recognizeLast(in drawing: PKDrawing) -> RecognizedShape? {
        guard let stroke = drawing.strokes.last else { return nil }
        return recognize(points: sampledPoints(of: stroke))
    }

    /// Evenly sampled points along a stroke, in page coordinates.
    static func sampledPoints(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(6))
            .map { $0.location.applying(stroke.transform) }
    }

    // MARK: - Core classification

    static func recognize(points raw: [CGPoint]) -> RecognizedShape? {
        let pts = dedupe(raw)
        guard pts.count >= 8 else { return nil }

        let bbox = boundingBox(pts)
        let diag = hypot(bbox.width, bbox.height)
        guard diag > 30 else { return nil }            // ignore tiny marks

        let start = pts.first!, end = pts.last!
        let gap = hypot(end.x - start.x, end.y - start.y)
        let len = pathLength(pts)
        guard len > 1 else { return nil }

        // Closed when the pen returns near where it started.
        let closed = gap < max(0.22 * len, 0.30 * min(bbox.width, bbox.height))

        if !closed {
            return recognizeOpen(pts, start: start, end: end, gap: gap, len: len)
        }
        return recognizeClosed(pts, bbox: bbox, diag: diag)
    }

    // MARK: Open strokes (line / arrow)

    private static func recognizeOpen(_ pts: [CGPoint], start: CGPoint, end: CGPoint,
                                      gap: CGFloat, len: CGFloat) -> RecognizedShape? {
        // A straight stroke hugs its own chord and barely doubles back.
        let straightness = maxDeviationFromChord(pts) / len
        guard gap > 0.80 * len, straightness < 0.14 else { return nil }

        if let tip = arrowTip(pts, start: start) {
            return .arrow(from: start, tip: tip)
        }
        return .line(start, end)
    }

    /// Detects a single-stroke arrowhead: the pen reaches a far tip, then flicks
    /// back to draw a barb. Returns the tip if such a reversal is present.
    private static func arrowTip(_ pts: [CGPoint], start: CGPoint) -> CGPoint? {
        // Index of the point farthest from the start — the candidate tip.
        var tipIdx = 0
        var tipDist: CGFloat = 0
        for (i, p) in pts.enumerated() {
            let d = hypot(p.x - start.x, p.y - start.y)
            if d > tipDist { tipDist = d; tipIdx = i }
        }
        // The tip must sit well before the end (so there's a tail = the barb),
        // and the tail must have real length relative to the shaft.
        guard tipIdx < pts.count - 2, tipIdx > pts.count / 2 else { return nil }
        let tail = pathLength(Array(pts[tipIdx...]))
        let shaft = pathLength(Array(pts[...tipIdx]))
        guard shaft > 1, tail > 0.10 * shaft, tail < 0.6 * shaft else { return nil }
        return pts[tipIdx]
    }

    // MARK: Closed strokes (rectangle / circle / triangle / diamond)

    private static func recognizeClosed(_ pts: [CGPoint], bbox: CGRect, diag: CGFloat) -> RecognizedShape? {
        let residual = ellipseResidual(pts, bbox: bbox)
        let corners = cornerCount(pts, diag: diag)
        switch corners {
        case 3:
            return .shape(.triangle, bbox)
        case 4:
            // A clean square's points sit ~0.15 off the inscribed ellipse, so only
            // a *very* round 4-corner blob (an RDP fluke) is a circle.
            if residual < 0.10 { return .shape(.circle, bbox) }
            return .shape(isDiamond(pts, bbox: bbox) ? .diamond : .rectangle, bbox)
        default:
            // No clean corner count — a smooth closed curve reads as a circle/ellipse.
            if residual < 0.18 { return .shape(.circle, bbox) }
            return nil
        }
    }

    /// Average normalized residual of each point against the ellipse inscribed in
    /// `bbox`. 0 = perfectly on the ellipse; larger = corners / straight edges.
    private static func ellipseResidual(_ pts: [CGPoint], bbox: CGRect) -> CGFloat {
        let a = bbox.width / 2, b = bbox.height / 2
        guard a > 1, b > 1 else { return .greatestFiniteMagnitude }
        let cx = bbox.midX, cy = bbox.midY
        var sum: CGFloat = 0
        for p in pts {
            let nx = (p.x - cx) / a, ny = (p.y - cy) / b
            sum += abs((nx * nx + ny * ny).squareRoot() - 1)
        }
        return sum / CGFloat(pts.count)
    }

    /// Counts sharp corners on a closed polygon, robust to where the stroke
    /// started: simplify with Ramer–Douglas–Peucker, then keep only vertices
    /// whose turn angle is sharp.
    private static func cornerCount(_ pts: [CGPoint], diag: CGFloat) -> Int {
        let simplified = rdp(pts, epsilon: 0.06 * diag)
        guard simplified.count >= 3 else { return simplified.count }
        // Drop a duplicated closing point so wrap-around neighbors are correct.
        var v = simplified
        if let f = v.first, let l = v.last, hypot(f.x - l.x, f.y - l.y) < 0.06 * diag {
            v.removeLast()
        }
        let n = v.count
        guard n >= 3 else { return n }
        var corners = 0
        for i in 0..<n {
            let prev = v[(i - 1 + n) % n]
            let cur = v[i]
            let next = v[(i + 1) % n]
            let a = CGPoint(x: prev.x - cur.x, y: prev.y - cur.y)
            let b = CGPoint(x: next.x - cur.x, y: next.y - cur.y)
            let turn = abs(angleBetween(a, b))
            // Interior angle far from straight (π) is a real corner.
            if abs(turn - .pi) > 0.62 { corners += 1 }   // ~35° off straight
        }
        return corners
    }

    /// A 4-corner closed shape is a diamond when its corners sit on the bounding
    /// box's edge midpoints (on the center axes) rather than at its corners.
    private static func isDiamond(_ pts: [CGPoint], bbox: CGRect) -> Bool {
        let cx = bbox.midX, cy = bbox.midY
        let hw = max(bbox.width / 2, 1), hh = max(bbox.height / 2, 1)
        // Vertices ≈ extreme points along the diagonals (corners) vs along the
        // axes (diamond). Score how axis-aligned the simplified corners are.
        let v = rdp(pts, epsilon: 0.06 * hypot(bbox.width, bbox.height))
        guard !v.isEmpty else { return false }
        var axisAligned = 0
        for p in v {
            let nx = abs(p.x - cx) / hw, ny = abs(p.y - cy) / hh
            if min(nx, ny) < 0.30 { axisAligned += 1 }   // near a center axis
        }
        return axisAligned * 2 >= v.count
    }

    // MARK: - Geometry helpers

    private static func dedupe(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        out.reserveCapacity(pts.count)
        for p in pts {
            if let last = out.last, hypot(p.x - last.x, p.y - last.y) < 1.5 { continue }
            out.append(p)
        }
        return out
    }

    private static func boundingBox(_ pts: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func pathLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var len: CGFloat = 0
        for i in 1..<pts.count {
            len += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
        }
        return len
    }

    /// Largest perpendicular distance from any point to the start→end chord.
    private static func maxDeviationFromChord(_ pts: [CGPoint]) -> CGFloat {
        guard let a = pts.first, let b = pts.last else { return 0 }
        var maxD: CGFloat = 0
        for p in pts { maxD = max(maxD, perpendicularDistance(p, a, b)) }
        return maxD
    }

    private static func perpendicularDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let denom = hypot(dx, dy)
        guard denom > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / denom
    }

    private static func angleBetween(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
    }

    /// Ramer–Douglas–Peucker polyline simplification.
    private static func rdp(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var dMax: CGFloat = 0, idx = 0
        for i in 1..<(pts.count - 1) {
            let d = perpendicularDistance(pts[i], pts.first!, pts.last!)
            if d > dMax { dMax = d; idx = i }
        }
        if dMax > epsilon {
            let left = rdp(Array(pts[...idx]), epsilon: epsilon)
            let right = rdp(Array(pts[idx...]), epsilon: epsilon)
            return left.dropLast() + right
        }
        return [pts.first!, pts.last!]
    }
}
