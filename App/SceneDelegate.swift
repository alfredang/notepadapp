import UIKit
import CloudKit

extension Notification.Name {
    /// Posted with a local `.notebook` file URL after a shared notebook link is
    /// accepted, so the SwiftUI layer (which holds the model context) imports it.
    static let notebookShareAccepted = Notification.Name("notebookShareAccepted")
}

/// Handles incoming iCloud share links (`CKShare`). SwiftUI manages the window;
/// this delegate exists only to receive `userDidAcceptCloudKitShareWith`, which
/// has no SwiftUI equivalent. It downloads the shared archive and hands it to the
/// app to import as a brand-new (duplicate) notebook.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await Self.accept(metadata) }
    }

    private static func accept(_ metadata: CKShare.Metadata) async {
        let container = CKContainer(identifier: NotebookShareService.containerID)
        do {
            try await container.accept(metadata)
            guard let rootID = metadata.hierarchicalRootRecordID ?? metadata.rootRecord?.recordID else { return }
            let record = try await container.sharedCloudDatabase.record(for: rootID)
            guard let asset = record["archive"] as? CKAsset, let source = asset.fileURL else { return }

            // CKAsset files are transient — copy to our temp dir before importing.
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("shared-\(UUID().uuidString)")
                .appendingPathExtension(NotebookArchiveService.fileExtension)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: source, to: dest)

            await MainActor.run {
                NotificationCenter.default.post(name: .notebookShareAccepted, object: dest)
            }
        } catch {
            // Best-effort: a failed accept just means nothing is imported.
        }
    }
}
