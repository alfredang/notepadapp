import UIKit

/// Rendering for the page background surface color.
extension PaperSurface {
    var uiColor: UIColor {
        switch self {
        case .whiteboard: .white
        case .paper: UIColor(red: 0.98, green: 0.96, blue: 0.86, alpha: 1) // warm cream
        case .blackboard: UIColor(red: 0.09, green: 0.16, blue: 0.13, alpha: 1) // chalkboard green-black
        }
    }
}

/// Rendering for the ruled overlay drawn on top of a surface. Line color adapts
/// to the surface (dark ink on light paper, light ink on a blackboard) so the
/// pattern stays visible on any surface.
extension PaperPattern {
    /// Ruling spacing (points), tuned to the A4 page width (794 pt).
    private static let gridSpacing: CGFloat = 32
    private static let dotSpacing: CGFloat = 28
    private static let lineSpacing: CGFloat = 40

    func draw(in rect: CGRect, context ctx: CGContext, onDark: Bool) {
        let lineColor = (onDark ? UIColor.white : UIColor.black)
        switch self {
        case .blank:
            break

        case .grid:
            ctx.saveGState()
            ctx.setStrokeColor(lineColor.withAlphaComponent(onDark ? 0.16 : 0.10).cgColor)
            ctx.setLineWidth(0.75)
            var x = rect.minX + Self.gridSpacing
            while x < rect.maxX {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += Self.gridSpacing
            }
            var y = rect.minY + Self.gridSpacing
            while y < rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += Self.gridSpacing
            }
            ctx.strokePath()
            ctx.restoreGState()

        case .dotted:
            ctx.saveGState()
            ctx.setFillColor(lineColor.withAlphaComponent(onDark ? 0.32 : 0.25).cgColor)
            let r: CGFloat = 1.3
            var y = rect.minY + Self.dotSpacing
            while y < rect.maxY {
                var x = rect.minX + Self.dotSpacing
                while x < rect.maxX {
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += Self.dotSpacing
                }
                y += Self.dotSpacing
            }
            ctx.restoreGState()

        case .lined:
            ctx.saveGState()
            let stroke = onDark
                ? UIColor.white.withAlphaComponent(0.18)
                : UIColor(red: 0.30, green: 0.45, blue: 0.85, alpha: 0.18)
            ctx.setStrokeColor(stroke.cgColor)
            ctx.setLineWidth(0.75)
            var y = rect.minY + Self.lineSpacing
            while y < rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += Self.lineSpacing
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}

/// A UIView that paints a page's paper template (surface color + ruled pattern).
/// Lives below the ink/overlay inside `PageContainerView`.
final class PaperBackgroundView: UIView {
    private var surface: PaperSurface = .whiteboard
    private var pattern: PaperPattern = .blank

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contentMode = .redraw
        backgroundColor = surface.uiColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(surface: PaperSurface, pattern: PaperPattern) {
        self.surface = surface
        self.pattern = pattern
        backgroundColor = surface.uiColor
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        pattern.draw(in: bounds, context: ctx, onDark: surface.isDark)
    }
}
