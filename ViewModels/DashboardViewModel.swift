import Foundation
import Observation
import SwiftData

/// Drives the dashboard: notebook listing, sorting, search and CRUD.
@MainActor
@Observable
final class DashboardViewModel {
    private let repository: any NotebookRepositoryProtocol
    /// When set, the view model browses this notebook's sub-notebooks instead of top-level.
    private let parent: Notebook?
    /// When true, lists starred notebooks (any depth) instead of a folder level.
    let favoritesOnly: Bool

    var notebooks: [Notebook] = []
    var sort: NotebookSort = .lastModified {
        didSet { reload() }
    }
    var searchText: String = ""
    /// Active tag filter (nil = show all).
    var selectedTag: String?
    var errorMessage: String?
    /// True while a fresh install / reinstall is waiting for SwiftData's first
    /// CloudKit import to populate the local store.
    var isRestoringFromCloud = false
    var hasCheckedCloudRestore = false
    @ObservationIgnored private var cloudRestoreTask: Task<Void, Never>?

    /// All tags used across the current notebooks, sorted, for the filter menu.
    var allTags: [String] {
        Array(Set(notebooks.flatMap { $0.tags })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    init(repository: any NotebookRepositoryProtocol, parent: Notebook? = nil, favoritesOnly: Bool = false) {
        self.repository = repository
        self.parent = parent
        self.favoritesOnly = favoritesOnly
        reload()
    }

    /// Notebooks after applying the current search filter. Matches the title or
    /// any recognized handwriting/text inside the notebook's pages.
    var filteredNotebooks: [Notebook] {
        var result = notebooks
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return result }
        return result.filter { notebook in
            notebook.title.localizedCaseInsensitiveContains(query)
                || notebook.orderedPages.contains {
                    $0.recognizedText.localizedCaseInsensitiveContains(query)
                }
        }
    }

    /// Updates a notebook's tags (trimmed, de-duplicated) and persists.
    func setTags(_ tags: [String], on notebook: Notebook) {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        notebook.tags = Array(NSOrderedSet(array: cleaned).array as? [String] ?? cleaned)
        notebook.touch()
        do {
            try repository.save()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        do {
            if favoritesOnly {
                notebooks = try repository.allFavorites(sortedBy: sort)
            } else if let parent {
                notebooks = parent.orderedChildren.sorted(by: sort.comparator)
            } else {
                notebooks = try repository.allTopLevel(sortedBy: sort)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stars / unstars a notebook and refreshes the listing.
    func toggleFavorite(_ notebook: Notebook) {
        do {
            try repository.setFavorite(notebook, !notebook.isFavorite)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Manual iCloud sync: flush any pending local edits up to CloudKit, then
    /// re-fetch so changes already imported from other devices show up. CloudKit
    /// performs the actual network fetch in the background; this pushes local
    /// changes immediately and surfaces whatever has landed locally.
    func syncNow() {
        do {
            try repository.save()
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
        if parent == nil, notebooks.isEmpty {
            restoreFromCloudIfNeeded(force: true)
        }
    }

    /// On a new iPad or after reinstall, SwiftData starts with an empty local
    /// store and imports the user's private CloudKit data asynchronously. Rather
    /// than blindly polling for a fixed window, drive the "Restoring…" state from
    /// CloudKit's real import events (`CloudSyncMonitor`): surface notebooks the
    /// instant the first batch lands, and — crucially — stop as soon as an import
    /// pass *completes with nothing to restore* or the device has no iCloud
    /// account, so the user never stares at an endless spinner.
    func restoreFromCloudIfNeeded(force: Bool = false) {
        guard parent == nil, !favoritesOnly, !isRestoringFromCloud else { return }
        guard force || !hasCheckedCloudRestore else { return }
        hasCheckedCloudRestore = true
        reload()
        guard notebooks.isEmpty else {
            isRestoringFromCloud = false
            return
        }

        let monitor = CloudSyncMonitor.shared
        monitor.refreshAccountStatus()
        // No iCloud account on this device → nothing will ever arrive. Skip the
        // spinner and let the empty state prompt the user to sign in.
        guard !monitor.iCloudUnavailable else {
            isRestoringFromCloud = false
            return
        }

        cloudRestoreTask?.cancel()
        isRestoringFromCloud = true
        cloudRestoreTask = Task { @MainActor in
            let importsAtStart = monitor.completedImports
            var lastSeenImports = importsAtStart
            var quietTicks = 0                 // seconds since the last import pass
            // Hard cap (~2 min) so a wedged sync can't spin forever.
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                reload()
                if !notebooks.isEmpty { break }            // data arrived
                if monitor.iCloudUnavailable { break }      // account went away
                if monitor.completedImports != lastSeenImports {
                    lastSeenImports = monitor.completedImports
                    quietTicks = 0                          // fresh activity — keep waiting
                } else if lastSeenImports > importsAtStart {
                    // An import pass finished and brought no notebooks. Give a short
                    // grace for follow-up batches, then conclude there's nothing to
                    // restore and fall back to the normal empty state.
                    quietTicks += 1
                    if quietTicks >= 8 { break }
                }
            }
            isRestoringFromCloud = false
        }
    }

    @discardableResult
    func createNotebook(title: String) -> Notebook? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Untitled Notebook" : name
        do {
            let notebook = try repository.create(title: finalName, parent: parent)
            reload()
            return notebook
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createSubNotebook(title: String, under parent: Notebook) -> Notebook? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Untitled Notebook" : name
        do {
            let notebook = try repository.create(title: finalName, parent: parent)
            reload()
            return notebook
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func rename(_ notebook: Notebook, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try repository.rename(notebook, to: name)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ notebook: Notebook) {
        do {
            try repository.delete(notebook)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ notebook: Notebook) {
        do {
            try repository.duplicate(notebook)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Migrates a PDF (exported / shared from GoodNotes, Notability, Apple Notes,
    /// or any app) into a brand-new notebook — one annotatable page per PDF page.
    func importPDF(from url: URL) {
        let backgrounds = PDFImportService.renderBackgrounds(from: url)
        guard !backgrounds.isEmpty else {
            errorMessage = "Couldn't read that PDF. Export it again from the other app and retry."
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        do {
            try repository.createFromBackgrounds(
                title: name.isEmpty ? "Imported Notebook" : name,
                backgrounds: backgrounds,
                parent: parent
            )
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports a shared `.notebook` archive as a new top-level notebook.
    func importArchive(from url: URL, into context: ModelContext) {
        do {
            try NotebookArchiveService.importArchive(from: url, into: context)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
