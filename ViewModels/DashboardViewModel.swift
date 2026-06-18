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

    init(repository: any NotebookRepositoryProtocol, parent: Notebook? = nil) {
        self.repository = repository
        self.parent = parent
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
            if let parent {
                notebooks = parent.orderedChildren.sorted(by: sort.comparator)
            } else {
                notebooks = try repository.allTopLevel(sortedBy: sort)
            }
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
    /// store and imports the user's private CloudKit data asynchronously. Keep
    /// refreshing for a short window so synced notebooks appear automatically
    /// instead of leaving the dashboard stuck on the empty state.
    func restoreFromCloudIfNeeded(force: Bool = false) {
        guard parent == nil, !isRestoringFromCloud else { return }
        guard force || !hasCheckedCloudRestore else { return }
        hasCheckedCloudRestore = true
        reload()
        guard notebooks.isEmpty else {
            isRestoringFromCloud = false
            return
        }

        cloudRestoreTask?.cancel()
        isRestoringFromCloud = true
        cloudRestoreTask = Task { @MainActor in
            for _ in 0..<45 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                reload()
                if !notebooks.isEmpty {
                    isRestoringFromCloud = false
                    return
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
