import SwiftUI

/// Creates an iCloud share link for a notebook and presents it for sharing.
/// Recipients who open the link get a **duplicate** copy in their own iCloud —
/// they can't edit the original.
struct ShareLinkSheet: View {
    let notebook: Notebook
    @Environment(\.dismiss) private var dismiss

    @State private var url: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    VStack(spacing: 20) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        Text("Share Link Ready").font(.headline)
                        Text("Anyone with this link gets their own copy of “\(notebook.title)”. Your notebook stays private — they can't change it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        ShareLink(item: url) {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(40)
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't Create Link", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else {
                    ProgressView("Creating share link…")
                }
            }
            .navigationTitle("Share a Copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do { url = try await NotebookShareService.createShareLink(for: notebook) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
