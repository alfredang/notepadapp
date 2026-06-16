import SwiftUI

/// The active editing tool.
enum EditorTool: Equatable {
    case pen
    case highlighter
    case eraserPixel
    case eraserObject
    case selection
    case shape(ShapeKind)
    case flowchart(ShapeKind)

    var isInking: Bool { self == .pen || self == .highlighter }
    var isEraser: Bool { self == .eraserPixel || self == .eraserObject }

    /// Whether this tool draws on the vector overlay rather than the PencilKit canvas.
    var isOverlayTool: Bool {
        switch self {
        case .shape, .flowchart, .selection: true
        default: false
        }
    }

    /// The overlay shape kind this tool creates, if any.
    var overlayKind: ShapeKind? {
        switch self {
        case .shape(let k), .flowchart(let k): k
        default: nil
        }
    }
}

/// What a double-tap (or squeeze) on the Apple Pencil does. Chosen in Settings.
enum PencilDoubleTapAction: String, CaseIterable, Identifiable {
    case undo
    case eraser
    case lasso
    case off

    var id: String { rawValue }

    /// The persisted preference (`@AppStorage` reads the raw string).
    static let storageKey = "pencilDoubleTapAction"

    var title: String {
        switch self {
        case .undo:   "Undo / Redo"
        case .eraser: "Switch to Eraser"
        case .lasso:  "Switch to Lasso"
        case .off:    "Off"
        }
    }

    static var current: PencilDoubleTapAction {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        return raw.flatMap(PencilDoubleTapAction.init(rawValue:)) ?? .eraser
    }
}

/// User-configurable defaults persisted in `UserDefaults`, shared between the
/// Settings screen and the code that applies them (the editor and the
/// new-notebook factory). Keeping the keys + fallbacks here avoids drift.
enum AppDefaults {
    static let penWidthKey = "defaultPenWidth"
    static let eraserWidthKey = "defaultEraserWidth"
    static let surfaceKey = "defaultPaperSurface"
    static let patternKey = "defaultPaperPattern"

    static var penWidth: CGFloat {
        let v = UserDefaults.standard.double(forKey: penWidthKey)
        return v > 0 ? v : 2
    }
    static var eraserWidth: CGFloat {
        let v = UserDefaults.standard.double(forKey: eraserWidthKey)
        return v > 0 ? v : 20
    }
    static var paperSurface: PaperSurface {
        UserDefaults.standard.string(forKey: surfaceKey)
            .flatMap(PaperSurface.init(rawValue:)) ?? .blackboard
    }
    static var paperPattern: PaperPattern {
        UserDefaults.standard.string(forKey: patternKey)
            .flatMap(PaperPattern.init(rawValue:)) ?? .blank
    }
}

/// Predefined pen widths (px), per spec.
enum ToolDefaults {
    static let penSizes: [CGFloat] = [1, 2, 4, 6, 8, 12, 16, 20]
    static let eraserSizes: [CGFloat] = [10, 20, 30, 45, 60]
    static let highlighterSizes: [CGFloat] = [5, 10, 20, 30]
    static let shapeWidths: [CGFloat] = [1, 2, 4, 6, 8, 10]

    /// Standard color palette, per spec.
    static let palette: [RGBAColor] = [
        .black,
        RGBAColor(red: 0.0, green: 0.48, blue: 1.0),   // Blue
        RGBAColor(red: 0.96, green: 0.26, blue: 0.21),  // Red
        RGBAColor(red: 0.30, green: 0.69, blue: 0.31),  // Green
        RGBAColor(red: 1.0, green: 0.60, blue: 0.0),    // Orange
        RGBAColor(red: 0.61, green: 0.15, blue: 0.69),  // Purple
        RGBAColor(red: 1.0, green: 0.84, blue: 0.0),    // Yellow
        RGBAColor(red: 0.50, green: 0.50, blue: 0.50)   // Gray
    ]

    /// A larger swatch set for the color picker dropdown.
    static let extendedPalette: [RGBAColor] = [
        // Neutrals
        RGBAColor(red: 0.00, green: 0.00, blue: 0.00), // Black
        RGBAColor(red: 0.27, green: 0.27, blue: 0.27), // Dark Gray
        RGBAColor(red: 0.50, green: 0.50, blue: 0.50), // Gray
        RGBAColor(red: 0.72, green: 0.72, blue: 0.72), // Light Gray
        RGBAColor(red: 0.90, green: 0.90, blue: 0.90), // Silver
        RGBAColor(red: 1.00, green: 1.00, blue: 1.00), // White
        // Reds / pinks
        RGBAColor(red: 0.80, green: 0.00, blue: 0.00), // Dark Red
        RGBAColor(red: 0.96, green: 0.26, blue: 0.21), // Red
        RGBAColor(red: 1.00, green: 0.45, blue: 0.45), // Salmon
        RGBAColor(red: 1.00, green: 0.34, blue: 0.66), // Pink
        RGBAColor(red: 0.85, green: 0.0,  blue: 0.52), // Magenta
        RGBAColor(red: 0.61, green: 0.15, blue: 0.69), // Purple
        // Oranges / yellows
        RGBAColor(red: 0.55, green: 0.27, blue: 0.07), // Brown
        RGBAColor(red: 1.00, green: 0.45, blue: 0.0),  // Dark Orange
        RGBAColor(red: 1.00, green: 0.60, blue: 0.0),  // Orange
        RGBAColor(red: 1.00, green: 0.76, blue: 0.03), // Amber
        RGBAColor(red: 1.00, green: 0.84, blue: 0.0),  // Yellow
        RGBAColor(red: 0.85, green: 0.85, blue: 0.20), // Lime
        // Greens / teals
        RGBAColor(red: 0.20, green: 0.55, blue: 0.20), // Dark Green
        RGBAColor(red: 0.30, green: 0.69, blue: 0.31), // Green
        RGBAColor(red: 0.18, green: 0.80, blue: 0.44), // Emerald
        RGBAColor(red: 0.0,  green: 0.74, blue: 0.74), // Teal
        // Blues
        RGBAColor(red: 0.0,  green: 0.48, blue: 1.00), // Blue
        RGBAColor(red: 0.10, green: 0.30, blue: 0.80), // Indigo
        RGBAColor(red: 0.40, green: 0.62, blue: 0.95), // Sky
        RGBAColor(red: 0.0,  green: 0.20, blue: 0.50)  // Navy
    ]
}
