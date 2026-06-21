import SwiftUI

/// A single notebook tile on the dashboard grid.
struct NotebookCard: View {
    let notebook: Notebook
    var onOpen: () -> Void
    var onOpenFolder: () -> Void
    var onRename: (String) -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onAddSubNotebook: () -> Void
    var onShare: () -> Void
    var onShareLink: () -> Void
    var onEditTags: () -> Void
    var onToggleFavorite: () -> Void

    @State private var isRenaming = false
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                NotebookCoverView(notebook: notebook)
                    .softShadow()
                    .overlay(alignment: .topTrailing) { favoriteBadge }
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel("Open \(notebook.title)")

            if isRenaming {
                TextField("Name", text: $draftTitle, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
            } else {
                Text(notebook.title)
                    .font(.headline)
                    .lineLimit(1)
            }

            if !notebook.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(notebook.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .imageScale(.small)
                Text("\(notebook.pageCount) pages")
                if notebook.orderedChildren.count > 0 {
                    Text("· \(notebook.orderedChildren.count) folders")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Updated \(notebook.updatedAt.relativeDescription)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color(.secondarySystemBackground))
        )
        .contextMenu {
            Button { onOpen() } label: { Label("Open", systemImage: "book") }
            Button { onToggleFavorite() } label: {
                Label(notebook.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: notebook.isFavorite ? "star.slash" : "star")
            }
            if notebook.orderedChildren.count > 0 {
                Button { onOpenFolder() } label: { Label("Open Sub-Notebooks", systemImage: "folder") }
            }
            Button { onShare() } label: { Label("Share Notebook", systemImage: "square.and.arrow.up") }
            Button { onShareLink() } label: { Label("Share Link (Copy)", systemImage: "link") }
            // Editing/creating/deleting notebooks is iPad-only; iPhone is view-only
            // so it can't alter the shared notebooks (the iPad is the source of truth).
            if DeviceKind.isPad {
                Button { beginRename() } label: { Label("Rename", systemImage: "pencil") }
                Button { onEditTags() } label: { Label("Edit Tags", systemImage: "tag") }
                Button { onAddSubNotebook() } label: { Label("Add Sub-Notebook", systemImage: "folder.badge.plus") }
                Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Divider()
                Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    /// A star button in the cover's top-right corner: filled when favorited,
    /// a subtle outline otherwise so it stays discoverable as a tap target.
    @ViewBuilder
    private var favoriteBadge: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: notebook.isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(notebook.isFavorite ? Color.yellow : Color.white)
                .padding(7)
                .background(.black.opacity(0.28), in: Circle())
                .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel(notebook.isFavorite ? "Remove \(notebook.title) from Favorites" : "Add \(notebook.title) to Favorites")
    }

    private func beginRename() {
        draftTitle = notebook.title
        isRenaming = true
    }

    private func commitRename() {
        isRenaming = false
        onRename(draftTitle)
    }
}
