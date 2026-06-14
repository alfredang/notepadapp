import Foundation
import Observation
import UIKit

/// Drives a single open notebook: page list and page management.
@MainActor
@Observable
final class NotebookViewModel {
    let notebook: Notebook
    private let repository: any PageRepositoryProtocol

    /// Index of the page currently focused in the editor.
    var selectedPageIndex: Int = 0
    /// Token bumped to invalidate thumbnails after edits.
    var refreshToken: Int = 0
    var errorMessage: String?

    init(notebook: Notebook, repository: any PageRepositoryProtocol) {
        self.notebook = notebook
        self.repository = repository
        // Ensure a notebook always has at least one page.
        if notebook.orderedPages.isEmpty {
            _ = try? repository.addPage(to: notebook, at: nil)
        }
    }

    var pages: [Page] { notebook.orderedPages }

    var selectedPage: Page? {
        guard pages.indices.contains(selectedPageIndex) else { return pages.first }
        return pages[selectedPageIndex]
    }

    // MARK: - Page actions

    func addPageAtEnd() {
        addPage(at: nil, like: pages.last)
        selectedPageIndex = pages.count - 1
    }

    func insertPage(before index: Int) {
        addPage(at: index, like: pages.indices.contains(index) ? pages[index] : nil)
        selectedPageIndex = index
    }

    func insertPage(after index: Int) {
        addPage(at: index + 1, like: pages.indices.contains(index) ? pages[index] : nil)
        selectedPageIndex = min(index + 1, pages.count - 1)
    }

    /// Adds a page at `index` (nil = end), inheriting the template from `like`
    /// (or the notebook) so a new page always matches its neighbour.
    private func addPage(at index: Int?, like neighbour: Page?) {
        do {
            let page = try repository.addPage(to: notebook, at: index)
            page.paperSurface = neighbour?.paperSurface ?? notebook.paperSurface
            page.paperPattern = neighbour?.paperPattern ?? notebook.paperPattern
            try repository.save()
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ page: Page) {
        perform { try repository.duplicate(page, in: notebook) }
    }

    func delete(_ page: Page) {
        guard pages.count > 1 else { return } // keep at least one page
        let removedIndex = pages.firstIndex { $0.id == page.id } ?? 0
        do {
            try repository.delete(page, from: notebook)
            selectedPageIndex = min(removedIndex, pages.count - 1)
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear(_ page: Page) {
        do {
            try repository.clear(page)
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears the strokes and shapes on every page in the notebook.
    func clearAllPages() {
        do {
            for page in pages { try repository.clear(page) }
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Switches the whole notebook's surface and recolors existing ink & shapes
    /// so they stay visible on the new surface (dark ink ⇄ white chalk).
    func setSurface(_ surface: PaperSurface) {
        notebook.paperSurface = surface
        let map: (UIColor) -> UIColor = { color in
            surface.isDark ? InkRecolor.forBlackboard(color) : InkRecolor.forWhitePaper(color)
        }
        for page in pages {
            page.paperSurface = surface
            page.drawingData = InkRecolor.recolorDrawing(page.drawingData, using: map)
            var items = page.items
            for i in items.indices {
                items[i].strokeColor = RGBAColor(map(items[i].strokeColor.uiColor))
            }
            page.items = items
            page.touch()
        }
        try? repository.save()
        bump()
    }

    /// Switches the whole notebook's ruled pattern (does not touch ink).
    func setPattern(_ pattern: PaperPattern) {
        notebook.paperPattern = pattern
        for page in pages {
            page.paperPattern = pattern
            page.touch()
        }
        try? repository.save()
        bump()
    }

    /// The notebook's current template (the source of truth for new pages).
    var paperSurface: PaperSurface { notebook.paperSurface }
    var paperPattern: PaperPattern { notebook.paperPattern }

    /// Deletes the pages with the given ids, always keeping at least one page.
    func deletePages(ids: Set<UUID>) {
        let targets = pages.filter { ids.contains($0.id) }
        for page in targets {
            guard pages.count > 1 else { break }
            do {
                try repository.delete(page, from: notebook)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if selectedPageIndex >= pages.count { selectedPageIndex = max(0, pages.count - 1) }
        bump()
    }

    func movePages(from source: IndexSet, to destination: Int) {
        do {
            try repository.move(in: notebook, from: source, to: destination)
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports a PDF, appending one annotatable page per PDF page.
    func importPDF(from url: URL) {
        let backgrounds = PDFImportService.renderBackgrounds(from: url)
        guard !backgrounds.isEmpty else {
            errorMessage = "Couldn't read that PDF."
            return
        }
        do {
            let firstNewIndex = pages.count
            try repository.appendPages(withBackgrounds: backgrounds, to: notebook)
            bump()
            selectedPageIndex = firstNewIndex
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Infinite / extendable canvas

    /// Grows the current page by one more A4 height (up to a sane cap).
    func extendCurrentPage() {
        guard let page = selectedPage else { return }
        page.heightUnits = min(page.heightUnits + 1, 12)
        page.touch()
        try? repository.save()
        bump()
    }

    /// Restores the current page to a single A4 height.
    func resetCurrentPageHeight() {
        guard let page = selectedPage, page.heightUnits != 1 else { return }
        page.heightUnits = 1
        page.touch()
        try? repository.save()
        bump()
    }

    func bump() { refreshToken &+= 1 }

    private func perform(_ action: () throws -> Page) {
        do {
            let page = try action()
            // New pages inherit the notebook's current template.
            if page.paperSurface != paperSurface || page.paperPattern != paperPattern {
                page.paperSurface = paperSurface
                page.paperPattern = paperPattern
                try? repository.save()
            }
            bump()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
