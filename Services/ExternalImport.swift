import Foundation
import SwiftData

extension Notification.Name {
    /// Posted after a file arriving from outside the app (AirDrop, "Open in
    /// NotePad", Files) is imported, so any visible dashboard can refresh.
    static let externalNotebookImported = Notification.Name("externalNotebookImported")
}

/// Handles files handed to the app from outside — AirDrop, "Open in NotePad",
/// or the Files app. A `.notebook` archive is restored; a PDF is migrated into a
/// new notebook (one annotatable page per PDF page).
@MainActor
enum ExternalImport {
    @discardableResult
    static func handle(url: URL, context: ModelContext) -> Bool {
        let ext = url.pathExtension.lowercased()
        do {
            if ext == NotebookArchiveService.fileExtension {
                try NotebookArchiveService.importArchive(from: url, into: context)
            } else if ext == "pdf" {
                // PDFImportService manages its own security-scoped access.
                let backgrounds = PDFImportService.renderBackgrounds(from: url)
                guard !backgrounds.isEmpty else { return false }
                let repository = NotebookRepository(context: context)
                try repository.createFromBackgrounds(
                    title: url.deletingPathExtension().lastPathComponent,
                    backgrounds: backgrounds,
                    parent: nil
                )
            } else {
                return false
            }
            NotificationCenter.default.post(name: .externalNotebookImported, object: nil)
            return true
        } catch {
            return false
        }
    }
}
