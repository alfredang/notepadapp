import Foundation
import SwiftData

/// A notebook. Supports nesting via a self-referential parent/children relationship.
@Model
final class Notebook {
    // CloudKit requires every attribute to be optional or carry a default value,
    // and forbids `.unique` constraints — UUIDs stay unique by generation.
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Manual ordering on the dashboard / within a parent.
    var sortIndex: Int = 0

    /// Starred by the user; surfaced in the Favorites tab. Defaulted for CloudKit.
    var isFavorite: Bool = false

    /// Free-form tags for grouping/filtering (e.g. Physics, Math, Computing).
    /// Defaulted for CloudKit compatibility.
    var tags: [String] = []

    /// The notebook's paper template; new pages inherit it. Stored as raw
    /// strings for CloudKit compatibility. `paperStyleRaw` is the legacy
    /// single-axis value, kept for migration.
    var paperStyleRaw: String = "white"
    var paperSurfaceRaw: String = ""
    var paperPatternRaw: String = ""
    var paperLayoutRaw: String = ""

    var paperSurface: PaperSurface {
        get { PaperSurface(rawValue: paperSurfaceRaw) ?? PaperTemplateMigration.surface(forLegacy: paperStyleRaw) }
        set { paperSurfaceRaw = newValue.rawValue }
    }
    var paperPattern: PaperPattern {
        get { PaperPattern(rawValue: paperPatternRaw) ?? PaperTemplateMigration.pattern(forLegacy: paperStyleRaw) }
        set { paperPatternRaw = newValue.rawValue }
    }
    var paperLayout: PaperLayout {
        get { PaperLayout(rawValue: paperLayoutRaw) ?? .portrait }
        set { paperLayoutRaw = newValue.rawValue }
    }

    /// Parent notebook for nesting (nil = top-level).
    @Relationship(inverse: \Notebook.children)
    var parent: Notebook?

    /// Sub-notebooks. Deleting a notebook cascades to its children.
    /// Optional because CloudKit requires every relationship to be optional.
    @Relationship(deleteRule: .cascade)
    var children: [Notebook]? = []

    /// Pages owned by this notebook. Deleting cascades to pages.
    /// Optional because CloudKit requires every relationship to be optional.
    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page]? = []

    /// Voice memos attached to this notebook. Deleting cascades to recordings.
    @Relationship(deleteRule: .cascade, inverse: \AudioNote.notebook)
    var audioNotes: [AudioNote]? = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortIndex: Int = 0,
        parent: Notebook? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
        self.parent = parent
        self.children = []
        self.pages = []
    }

    var pageCount: Int { pages?.count ?? 0 }

    /// Pages sorted by their index, for stable display.
    var orderedPages: [Page] {
        (pages ?? []).sorted { $0.pageIndex < $1.pageIndex }
    }

    /// Child notebooks sorted for stable display.
    var orderedChildren: [Notebook] {
        (children ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Voice memos, newest first.
    var orderedAudioNotes: [AudioNote] {
        (audioNotes ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func touch(_ date: Date = .now) {
        updatedAt = date
    }
}
