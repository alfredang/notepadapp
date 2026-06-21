import CloudKit
import Foundation

/// Creates an iCloud **share link** for a notebook. The link points at a
/// read-only CKShare wrapping a `.notebook` archive in the sender's private
/// CloudKit database; when a recipient opens it, the app saves a **duplicate**
/// into their own iCloud (see `SceneDelegate`). The original is never editable
/// by anyone else — they only ever get a copy.
@MainActor
enum NotebookShareService {
    static let containerID = "iCloud.com.tertiaryinfotech.notepadapp"
    static let recordType = "SharedNotebook"
    static let zoneName = "SharedNotebooks"

    private static var container: CKContainer { CKContainer(identifier: containerID) }
    private static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    enum ShareError: LocalizedError {
        case noURL
        case notSignedIn
        var errorDescription: String? {
            switch self {
            case .noURL: "Couldn't create a share link. Please try again."
            case .notSignedIn: "Sign in to iCloud to create a share link."
            }
        }
    }

    /// Serializes `notebook`, uploads it as a read-only CKShare, and returns the
    /// iCloud share URL to hand to a share sheet.
    static func createShareLink(for notebook: Notebook) async throws -> URL {
        guard try await container.accountStatus() == .available else { throw ShareError.notSignedIn }

        let fileURL = try NotebookArchiveService.export(notebook)
        let db = container.privateCloudDatabase

        // Sharing requires a custom zone (the default zone can't be shared).
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])

        let title = notebook.title.isEmpty ? "Notebook" : notebook.title
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(zoneID: zoneID))
        record["title"] = title as CKRecordValue
        record["archive"] = CKAsset(fileURL: fileURL)

        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .readOnly   // anyone with the link gets a read-only copy

        let result = try await db.modifyRecords(saving: [record, share], deleting: [])
        for (_, res) in result.saveResults {
            if case .success(let saved) = res, let savedShare = saved as? CKShare, let url = savedShare.url {
                return url
            }
        }
        // Fall back to the in-memory share's url if the results didn't surface it.
        if let url = share.url { return url }
        throw ShareError.noURL
    }
}
