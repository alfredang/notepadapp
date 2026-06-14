import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// An open notebook: thumbnail sidebar + page editor, with page/export actions.
struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    let notebook: Notebook

    /// iPhone (and other compact-width contexts) get a sheet sidebar + scrollable
    /// toolbar; iPad/Mac (regular) keep the inline split layout.
    private var isCompact: Bool { hSizeClass == .compact }

    @State private var notebookVM: NotebookViewModel
    @State private var editorVM = EditorViewModel()
    @State private var controller = CanvasController()
    @State private var autoSave: AutoSaveService
    @State private var showSidebar = false
    /// Persisted finger-drawing preference (shared with Settings). Off by
    /// default so a finger scrolls and never creates strokes/shapes.
    @AppStorage("allowsFingerDrawing") private var allowsFingerDrawing = false
    @State private var showAudioNotes = false
    @State private var showPDFImporter = false
    @State private var exportItem: ExportRequest?

    init(notebook: Notebook) {
        self.notebook = notebook
        // Build dependencies from the shared context.
        let context = notebook.modelContext ?? ModelContext(try! ModelContainer(for: Notebook.self, Page.self, AudioNote.self))
        _notebookVM = State(initialValue: NotebookViewModel(
            notebook: notebook,
            repository: PageRepository(context: context)
        ))
        _autoSave = State(initialValue: AutoSaveService(context: context))
    }

    var body: some View {
        HStack(spacing: 0) {
            // iPad / Mac: inline split sidebar. iPhone: sidebar is a sheet (below).
            if showSidebar && !isCompact {
                SidebarView(viewModel: notebookVM)
                    .transition(.move(edge: .leading))
                Divider()
            }
            EditorView(
                pages: notebookVM.pages,
                editor: editorVM,
                autoSave: autoSave,
                controller: controller,
                structureToken: notebookVM.refreshToken
            )
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: Binding(
            get: { showSidebar && isCompact },
            set: { if !$0 { showSidebar = false } }
        )) {
            NavigationStack {
                SidebarView(viewModel: notebookVM, inSheet: true)
                    .navigationTitle("Pages")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSidebar = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: notebookVM.selectedPageIndex) { _, newValue in
            controller.scrollToPage(newValue)
            if isCompact { showSidebar = false }   // close the sheet after jumping
        }
        .onAppear {
            // Swiping up past the last page appends a new blank page; swiping
            // down past the first page inserts one above.
            controller.requestNewPageAtEnd = {
                notebookVM.addPageAtEnd()
            }
            controller.requestNewPageAtStart = {
                notebookVM.insertPage(before: 0)
            }
            controller.requestNewPageAbove = {
                let i = controller.currentVisiblePage()
                    .flatMap { p in notebookVM.pages.firstIndex { $0.id == p.id } } ?? 0
                notebookVM.insertPage(before: i)
            }
            controller.requestNewPageBelow = {
                let i = controller.currentVisiblePage()
                    .flatMap { p in notebookVM.pages.firstIndex { $0.id == p.id } } ?? (notebookVM.pages.count - 1)
                notebookVM.insertPage(after: i)
            }
            // Only the iPad (with Apple Pencil) edits. iPhone and Mac are
            // view-only — the canvas accepts scroll/zoom but no drawing, selection,
            // or template edits, so notes can't be messed up while reviewing them.
            editorVM.isEditable = DeviceKind.isPad
            editorVM.allowsFingerDrawing = DeviceKind.isPad ? allowsFingerDrawing : false
            // Default ink to the notebook's surface so it's visible (white
            // chalk on a blackboard, black on white paper).
            let ink = notebookVM.paperSurface.defaultInkColor
            editorVM.penColor = ink
            editorVM.shapeStrokeColor = ink
            // Wire the in-toolbar template control + thumbnail refresh.
            controller.currentPaperSurface = { notebookVM.paperSurface }
            controller.currentPaperPattern = { notebookVM.paperPattern }
            controller.setPaperSurface = { surface in
                notebookVM.setSurface(surface)
                controller.reloadAllPages()
                editorVM.penColor = surface.defaultInkColor
                editorVM.shapeStrokeColor = surface.defaultInkColor
            }
            controller.setPaperPattern = { pattern in
                notebookVM.setPattern(pattern)
                controller.reloadAllPages()
            }
            controller.currentPaperLayout = { notebookVM.paperLayout }
            controller.setPaperLayout = { layout in
                notebookVM.setLayout(layout)
                controller.relayoutPages()
            }
            controller.refreshThumbnails = { notebookVM.bump() }
            controller.deleteVisiblePage = {
                if let p = controller.currentVisiblePage() { notebookVM.delete(p) }
            }
        }
        .onChange(of: allowsFingerDrawing) { _, newValue in
            guard DeviceKind.isPad else { return }   // iPhone / Mac stay view-only
            editorVM.allowsFingerDrawing = newValue
            controller.applyTool()
        }
        .onDisappear { autoSave.saveNow() }
        .sheet(item: $exportItem) { request in
            ExportSheet(request: request)
        }
        .sheet(isPresented: $showAudioNotes) {
            AudioNotesView(notebook: notebook)
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                notebookVM.importPDF(from: url)
                controller.scrollToPage(notebookVM.selectedPageIndex)
            }
        }
    }


    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel("Toggle pages sidebar")
        }
        // Editing controls only on the iPad (iPhone / Mac are view-only).
        if DeviceKind.isPad {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $allowsFingerDrawing) {
                    Image(systemName: "hand.draw")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Finger drawing")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        notebookVM.extendCurrentPage()
                        controller.scrollToPage(notebookVM.selectedPageIndex)
                    } label: { Label("Extend Page", systemImage: "arrow.down.to.line") }
                    Button {
                        notebookVM.resetCurrentPageHeight()
                    } label: { Label("Reset Page Height", systemImage: "arrow.up.to.line") }
                } label: {
                    Image(systemName: "rectangle.expand.vertical")
                }
                .accessibilityLabel("Page size")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPDFImporter = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .accessibilityLabel("Import PDF")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showAudioNotes = true
            } label: {
                Image(systemName: "waveform")
            }
            .accessibilityLabel("Audio notes")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let page = notebookVM.selectedPage {
                    Section("Export Page") {
                        Button("PNG") { exportItem = .page(page, .png) }
                        Button("JPG") { exportItem = .page(page, .jpg) }
                        Button("PDF") { exportItem = .page(page, .pdf) }
                    }
                }
                Section("Export Notebook") {
                    Button("PDF") { exportItem = .notebook(notebook) }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Export")
        }
    }
}
