import SwiftUI
import SwiftData

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
    @State private var showingImporter = false
    /// Notebook whose tags are being edited.
    @State private var taggingNotebook: Notebook?
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
                            onEditTags: { taggingNotebook = notebook }
                        )
                    }
                }
                .padding(24)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search notebooks & handwriting")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                Text("Powered by Tertiary Infotech Academy Pte Ltd")
                Text("NotePad \(Self.appVersion)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.bar)
        }
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
        .alert("New Notebook", isPresented: $showingNewNotebook) {
            TextField("Notebook name", text: $newNotebookName)
            Button("Create") {
                if let notebook = viewModel.createNotebook(title: newNotebookName) {
                    notebookToOpenAfterCreate = notebook
                }
                newNotebookName = ""
            }
            Button("Cancel", role: .cancel) { newNotebookName = "" }
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
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [NotebookArchiveService.contentType]
        ) { result in
            if case .success(let url) = result {
                viewModel.importArchive(from: url, into: modelContext)
            }
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
        if !viewModel.allTags.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter by tag", selection: $viewModel.selectedTag) {
                        Text("All Notebooks").tag(String?.none)
                        ForEach(viewModel.allTags, id: \.self) { tag in
                            Label(tag, systemImage: "tag").tag(String?.some(tag))
                        }
                    }
                } label: {
                    Label("Filter by tag",
                          systemImage: viewModel.selectedTag == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                runSync()
            } label: {
                if syncFeedback == .syncing || sync.isSyncing {
                    ProgressView()
                } else {
                    Label("Sync with iCloud", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(syncFeedback == .syncing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(NotebookSort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingImporter = true
            } label: {
                Label("Import Notebook", systemImage: "square.and.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingNewNotebook = true
            } label: {
                Label("New Notebook", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var emptyState: some View {
        Group {
            if viewModel.isRestoringFromCloud {
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
                    Text("Your notebooks sync through iCloud. Sign in to iCloud in Settings to restore and back them up. You can still create notebooks on this device.")
                } actions: {
                    Button("Create Notebook") { showingNewNotebook = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("No Notebooks", systemImage: "book.closed")
                } description: {
                    Text("Create your first notebook to start taking notes.")
                } actions: {
                    HStack {
                        Button("Sync with iCloud") { runSync() }
                            .buttonStyle(.borderedProminent)
                        Button("Create Notebook") { showingNewNotebook = true }
                    }
                }
            }
        }
        .padding(.top, 80)
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
