import Foundation
import SwiftData
import CoreGraphics

/// A page's background surface (color). Independent of the ruled `PaperPattern`
/// drawn on top, so any surface can be combined with any pattern.
enum PaperSurface: String, CaseIterable, Identifiable, Sendable {
    case whiteboard
    case paper          // warm cream
    case blackboard     // dark chalkboard green

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whiteboard: "Whiteboard"
        case .paper: "Paper"
        case .blackboard: "Blackboard"
        }
    }

    /// Whether the surface is a dark (blackboard) template.
    var isDark: Bool { self == .blackboard }

    /// A sensible default ink color so strokes are visible on this surface
    /// (dark ink on light paper, white chalk on a blackboard).
    var defaultInkColor: RGBAColor {
        isDark ? RGBAColor(red: 1, green: 1, blue: 1) : .black
    }
}

/// A ruled overlay drawn on top of the page surface.
enum PaperPattern: String, CaseIterable, Identifiable, Sendable {
    case blank
    case lined
    case dotted
    case grid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: "Blank"
        case .lined: "Lined"
        case .dotted: "Dotted"
        case .grid: "Grid"
        }
    }
}

/// A single A4 page. Stores the PencilKit drawing as raw data and the vector
/// overlay items as JSON-encoded `Data`.
@Model
final class Page {
    // CloudKit requires every attribute to be optional or carry a default value,
    // and forbids `.unique` constraints — UUIDs stay unique by generation.
    var id: UUID = UUID()
    var pageIndex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// Serialized `PKDrawing` (`drawing.dataRepresentation()`).
    @Attribute(.externalStorage) var drawingData: Data = Data()

    /// JSON-encoded `[CanvasItem]` for the shape/flowchart overlay.
    @Attribute(.externalStorage) var shapesData: Data = Data()

    /// Text recognized from the handwriting + shape labels (Vision OCR), kept in
    /// sync after edits so the dashboard can search inside notes.
    var recognizedText: String = ""

    /// Optional page background raster (PNG) — e.g. an imported PDF page that the
    /// user annotates on top of. Empty for blank pages.
    @Attribute(.externalStorage) var backgroundData: Data = Data()

    /// How many stacked A4 heights this page spans. 1 = a standard page; larger
    /// values give an extended, continuous ("infinite") vertical canvas.
    var heightUnits: Int = 1

    /// Legacy single-axis template string (e.g. "white", "blackboard", "grid").
    /// Kept for CloudKit back-compat / migration; new code reads `paperSurface`
    /// and `paperPattern`.
    var paperStyleRaw: String = "white"

    /// The page's background surface. Stored raw for CloudKit; empty ⇒ derive
    /// from the legacy `paperStyleRaw`.
    var paperSurfaceRaw: String = ""

    /// The page's ruled overlay. Stored raw for CloudKit; empty ⇒ derive from
    /// the legacy `paperStyleRaw`.
    var paperPatternRaw: String = ""

    /// Owning notebook (inverse of `Notebook.pages`).
    var notebook: Notebook?

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        drawingData: Data = Data(),
        shapesData: Data = Data(),
        recognizedText: String = "",
        backgroundData: Data = Data(),
        heightUnits: Int = 1,
        surface: PaperSurface = .whiteboard,
        pattern: PaperPattern = .blank,
        notebook: Notebook? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.drawingData = drawingData
        self.shapesData = shapesData
        self.recognizedText = recognizedText
        self.backgroundData = backgroundData
        self.heightUnits = heightUnits
        self.paperSurfaceRaw = surface.rawValue
        self.paperPatternRaw = pattern.rawValue
        self.notebook = notebook
    }

    /// The page's background surface (migrating legacy templates on read).
    var paperSurface: PaperSurface {
        get { PaperSurface(rawValue: paperSurfaceRaw) ?? PaperTemplateMigration.surface(forLegacy: paperStyleRaw) }
        set { paperSurfaceRaw = newValue.rawValue }
    }

    /// The page's ruled overlay pattern (migrating legacy templates on read).
    var paperPattern: PaperPattern {
        get { PaperPattern(rawValue: paperPatternRaw) ?? PaperTemplateMigration.pattern(forLegacy: paperStyleRaw) }
        set { paperPatternRaw = newValue.rawValue }
    }

    /// The page's canvas size in points — A4 width, height scaled by `heightUnits`.
    var canvasSize: CGSize {
        CGSize(width: PageGeometry.a4.width, height: PageGeometry.a4.height * CGFloat(max(1, heightUnits)))
    }

    /// Decoded overlay items. Setting re-encodes to `shapesData`.
    var items: [CanvasItem] {
        get {
            guard !shapesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([CanvasItem].self, from: shapesData)) ?? []
        }
        set {
            shapesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func touch(_ date: Date = .now) {
        updatedAt = date
        notebook?.touch(date)
    }
}

/// Maps the old single-axis template strings onto the new surface + pattern
/// axes so pages created before the split keep their appearance.
enum PaperTemplateMigration {
    static func surface(forLegacy raw: String) -> PaperSurface {
        raw == "blackboard" ? .blackboard : .whiteboard
    }

    static func pattern(forLegacy raw: String) -> PaperPattern {
        switch raw {
        case "grid": .grid
        case "dotted": .dotted
        case "lined": .lined
        default: .blank
        }
    }
}
