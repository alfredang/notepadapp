import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Navigation route values for the dashboard stack.
enum DashboardRoute: Hashable {
    case editor(Notebook)
    case folder(Notebook)
}

/// Home screen: a grid of notebooks with create / sort / search.
/// Reused for sub-notebook folders via `parent`.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// Live CloudKit sync status (drives the toolbar indicator + auto-refresh).
    @State private var sync = CloudSyncMonitor.shared
    @State private var viewModel: DashboardViewModel
    @State private var path = NavigationPath()
    @State private var showingNewNotebook = false
    @State private var newNotebookName = ""
    @State private var notebookToOpenAfterCreate: Notebook?
    @State private var showingSettings = false
    /// Pending deletion awaiting confirmation.
    @State private var pendingDelete: Notebook?
    /// Notebook archive to share via the export sheet.
    @State private var shareItem: ExportRequest?
    /// `.notebook` archive importer.
    @State private var showingImporter = false
    /// PDF importer (PDF / GoodNotes / Notability / Apple Notes migration).
    @State private var showingPDFImporter = false
    /// Notebook whose tags are being edited.
    @State private var taggingNotebook: Notebook?
    /// Notebook being shared as an iCloud copy-link.
    @State private var shareLinkNotebook: Notebook?
    /// Transient banner shown when the user taps the sync button.
    @State private var syncFeedback: SyncFeedback?

    /// Status shown in the sync toast.
    enum SyncFeedback: Equatable {
        case syncing
        case updated
        case failed(String)
    }

    private let title: String

    init(viewModel: DashboardViewModel, title: String = "Notebooks") {
        _viewModel = State(initialValue: viewModel)
        self.title = title
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)]

    /// Marketing version + build, shown in the footer so the running version is
    /// visible at a glance (e.g. "v1.4 (9)").
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(title)
                // Hide the app tab bar the moment we navigate into a notebook/folder
                // (in sync with the push) so it doesn't flash then vanish — the
                // editor also pins it hidden, keeping it gone for the whole stack.
                .toolbar(path.isEmpty ? .automatic : .hidden, for: .tabBar)
                .navigationDestination(for: DashboardRoute.self) { route in
                    switch route {
                    case .editor(let notebook):
                        NotebookView(notebook: notebook)
                    case .folder(let notebook):
                        SubNotebookView(parent: notebook)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            if viewModel.filteredNotebooks.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(viewModel.filteredNotebooks) { notebook in
                        NotebookCard(
                            notebook: notebook,
                            onOpen: { path.append(DashboardRoute.editor(notebook)) },
                            onOpenFolder: { path.append(DashboardRoute.folder(notebook)) },
                            onRename: { viewModel.rename(notebook, to: $0) },
                            onDuplicate: { viewModel.duplicate(notebook) },
                            onDelete: { pendingDelete = notebook },
                            onAddSubNotebook: {
                                if let child = viewModel.createSubNotebook(title: "Untitled Notebook", under: notebook) {
                                    path.append(DashboardRoute.editor(child))
                                }
                            },
                            onShare: { shareItem = .notebookArchive(notebook) },
                            onShareLink: { shareLinkNotebook = notebook },
                            onEditTags: { taggingNotebook = notebook },
                            onToggleFavorite: { viewModel.toggleFavorite(notebook) }
                        )
                    }
                }
                .padding(24)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search notebooks & handwriting")
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { syncToast }
        .animation(.spring(duration: 0.3), value: syncFeedback)
        .task {
            sync.refreshAccountStatus()
            viewModel.restoreFromCloudIfNeeded()
        }
        // A remote import finished → surface the newly synced notebooks.
        .onChange(of: sync.lastImportDate) { _, _ in viewModel.reload() }
        // Returning to the app triggers CloudKit's foreground fetch; refresh too.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sync.refreshAccountStatus()
                viewModel.reload()
                viewModel.restoreFromCloudIfNeeded()
            }
        }
        .onChange(of: showingNewNotebook) { _, isShowing in
            guard !isShowing, let notebook = notebookToOpenAfterCreate else { return }
            notebookToOpenAfterCreate = nil
            path.append(DashboardRoute.editor(notebook))
        }
        // A sheet (not an .alert) so a long name can't push the Create button
        // behind the keyboard — Create lives in the nav bar and is always reachable.
        .sheet(isPresented: $showingNewNotebook) {
            NewNotebookSheet(name: $newNotebookName) {
                if let notebook = viewModel.createNotebook(title: newNotebookName) {
                    notebookToOpenAfterCreate = notebook
                }
                newNotebookName = ""
                showingNewNotebook = false
            } onCancel: {
                newNotebookName = ""
                showingNewNotebook = false
            }
        }
        .alert(
            "Delete \(pendingDelete?.title ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let nb = pendingDelete { viewModel.delete(nb) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently deletes the notebook and all of its pages and sub-notebooks.")
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(item: $shareItem) { request in
            ExportSheet(request: request)
        }
        .sheet(item: $taggingNotebook) { nb in
            TagEditorView(title: nb.title, currentTags: nb.tags, suggestions: viewModel.allTags) {
                viewModel.setTags($0, on: nb)
            }
        }
        .sheet(item: $shareLinkNotebook) { nb in
            ShareLinkSheet(notebook: nb)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [NotebookArchiveService.contentType]
        ) { result in
            if case .success(let url) = result {
                viewModel.importArchive(from: url, into: modelContext)
            }
        }
        .fileImporter(
            isPresented: $showingPDFImporter,
            allowedContentTypes: [.pdf]
        ) { result in
            if case .success(let url) = result {
                viewModel.importPDF(from: url)
            }
        }
        // A file imported elsewhere (AirDrop / Open in NotePad) → refresh the list.
        .onReceive(NotificationCenter.default.publisher(for: .externalNotebookImported)) { _ in
            viewModel.reload()
        }
    }

    /// Runs a manual iCloud sync and shows a transient status banner: a spinner
    /// while it works, then "Notebooks updated" (or an error). The on-device
    /// CloudKit fetch is asynchronous, so we give it a short window before
    /// re-reading and reporting the result.
    private func runSync() {
        guard syncFeedback != .syncing else { return }
        syncFeedback = .syncing
        viewModel.syncNow()                 // push local changes + refresh now
        Task {
            try? await Task.sleep(for: .seconds(2))   // let CloudKit import land
            viewModel.reload()
            if let error = sync.lastErrorMessage {
                syncFeedback = .failed(error)
            } else {
                syncFeedback = .updated
            }
            try? await Task.sleep(for: .seconds(2))
            if syncFeedback != .syncing { syncFeedback = nil }
        }
    }

    @ViewBuilder
    private var syncToast: some View {
        if let syncFeedback {
            HStack(spacing: 8) {
                switch syncFeedback {
                case .syncing:
                    ProgressView()
                    Text("Syncing with iCloud…")
                case .updated:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Notebooks updated")
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Sync failed: \(message)").lineLimit(2)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 6, y: 2)
            .padding(.bottom, 56)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        // Secondary actions (sort, tag filter, manual sync) live in a single
        // "More" menu so the primary Import / New buttons always stay visible —
        // the iPad's centered tab bar leaves little room on the trailing edge.
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(NotebookSort.allCases) { Text($0.rawValue).tag($0) }
                }
                if !viewModel.allTags.isEmpty {
                    Picker("Filter by tag", selection: $viewModel.selectedTag) {
                        Text("All Notebooks").tag(String?.none)
                        ForEach(viewModel.allTags, id: \.self) { tag in
                            Label(tag, systemImage: "tag").tag(String?.some(tag))
                        }
                    }
                }
                Divider()
                Button {
                    runSync()
                } label: {
                    Label("Sync with iCloud", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncFeedback == .syncing)
            } label: {
                if syncFeedback == .syncing || sync.isSyncing {
                    ProgressView()
                } else {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        // Import / migrate — iPad-only (iPhone & Mac are view-only).
        if DeviceKind.isPad && !viewModel.favoritesOnly {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Migrate from another app") {
                        Button { showingPDFImporter = true } label: {
                            Label("GoodNotes (PDF)…", systemImage: "doc.richtext")
                        }
                        Button { showingPDFImporter = true } label: {
                            Label("Notability (PDF)…", systemImage: "doc.richtext")
                        }
                        Button { showingPDFImporter = true } label: {
                            Label("Apple Notes (PDF)…", systemImage: "doc.richtext")
                        }
                    }
                    Section {
                        Button { showingPDFImporter = true } label: {
                            Label("Import PDF…", systemImage: "doc")
                        }
                        Button { showingImporter = true } label: {
                            Label("Import Notebook (.notebook)…", systemImage: "books.vertical")
                        }
                    }
                    Section {
                        Label("Tip: AirDrop a PDF or .notebook to this iPad and choose NotePad to import.",
                              systemImage: "dot.radiowaves.left.and.right")
                    }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            // Creating notebooks is iPad-only; iPhone is view-only.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewNotebook = true
                } label: {
                    Label("New Notebook", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private var emptyState: some View {
        Group {
            if viewModel.favoritesOnly {
                ContentUnavailableView {
                    Label("No Favorites", systemImage: "star")
                } description: {
                    Text("Tap the star on a notebook to add it here for quick access.")
                }
            } else if viewModel.isRestoringFromCloud {
                VStack(spacing: 14) {
                    ProgressView()
                    ContentUnavailableView {
                        Label("Syncing Notebooks", systemImage: "icloud.and.arrow.down")
                    } description: {
                        Text("Restoring your notebooks from iCloud.")
                    }
                }
            } else if sync.iCloudUnavailable {
                ContentUnavailableView {
                    Label("Sign in to iCloud", systemImage: "icloud.slash")
                } description: {
                    Text("Your notebooks sync through iCloud. Sign in to iCloud in Settings to restore and back them up.")
                } actions: {
                    if DeviceKind.isPad {
                        Button("Create Notebook") { showingNewNotebook = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Notebooks", systemImage: "book.closed")
                } description: {
                    Text(DeviceKind.isPad
                         ? "Create your first notebook to start taking notes."
                         : "Create notebooks on your iPad — they'll appear here once iCloud syncs.")
                } actions: {
                    HStack {
                        Button("Sync with iCloud") { runSync() }
                            .buttonStyle(.borderedProminent)
                        if DeviceKind.isPad {
                            Button("Create Notebook") { showingNewNotebook = true }
                        }
                    }
                }
            }
        }
        .padding(.top, 80)
    }
}

/// Sheet for naming a new notebook. Replaces the old `.alert` TextField, whose
/// Create button could slide behind the keyboard with longer names. Here Create
/// sits in the navigation bar and is always tappable.
private struct NewNotebookSheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Notebook name", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if !trimmed.isEmpty { onCreate() } }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate() }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

/// A nested dashboard scoped to one notebook's sub-notebooks.
struct SubNotebookView: View {
    @Environment(\.modelContext) private var modelContext
    let parent: Notebook

    var body: some View {
        DashboardView(
            viewModel: DashboardViewModel(
                repository: NotebookRepository(context: modelContext),
                parent: parent
            ),
            title: parent.title
        )
    }
}
