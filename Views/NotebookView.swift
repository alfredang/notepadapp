import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// An open notebook: thumbnail sidebar + page editor, with page/export actions.
struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.dismiss) private var dismiss
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
    /// Shown when "Insert Image" is tapped but the clipboard has no image.
    @State private var showNoImageAlert = false
    /// Presents the iCloud copy-link share sheet.
    @State private var showShareLink = false

    init(notebook: Notebook) {
        self.notebook = notebook
        // Build dependencies from the shared context.
        let context = notebook.modelContext ?? ModelContext(try! ModelContainer(for: Notebook.self, Page.self, AudioNote.self, AppSettings.self))
        _notebookVM = State(initialValue: NotebookViewModel(
            notebook: notebook,
            repository: PageRepository(context: context)
        ))
        _autoSave = State(initialValue: AutoSaveService(context: context))
    }

    var body: some View {
        VStack(spacing: 0) {
            // A custom header replaces the system navigation bar so opening a
            // notebook has NO chrome to reconfigure mid-transition — the whole
            // editor (header included) slides in as one stable layer, with no
            // tab-bar/nav-bar flash or top-section "jump".
            editorHeader
            Divider()
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
        }
        // Hide both system bars: the editor is fully self-chromed now.
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .alert("No image to paste", isPresented: $showNoImageAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy an image first (in Photos, Safari, Files…), then tap Insert Image to paste it onto this page.")
        }
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
            // Seed pen / eraser sizes from the user's defaults.
            editorVM.penWidth = AppDefaults.penWidth
            editorVM.eraserWidth = AppDefaults.eraserWidth
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
        .sheet(isPresented: $showShareLink) {
            ShareLinkSheet(notebook: notebook)
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


    /// Custom editor header — replaces the system navigation bar so there's no
    /// system chrome to reconfigure during the push (the source of the "jump").
    private var editorHeader: some View {
        ZStack {
            Text(notebook.title)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 132)   // stay clear of the edge controls

            HStack(spacing: 18) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back to notebooks")
                Button { withAnimation { showSidebar.toggle() } } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Toggle pages sidebar")

                Spacer()

                // Editing controls only on the iPad (iPhone / Mac are view-only).
                if DeviceKind.isPad {
                    Toggle(isOn: $allowsFingerDrawing) { Image(systemName: "hand.draw") }
                        .toggleStyle(.button)
                        .accessibilityLabel("Finger drawing")
                    Button { insertPastedImage() } label: { Image(systemName: "photo.badge.plus") }
                        .accessibilityLabel("Insert Image")
                }
                exportMenu
                if DeviceKind.isPad { moreMenu }
            }
        }
        .font(.system(size: 18))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Rectangle().fill(.bar).ignoresSafeArea(edges: .top))
    }

    /// Export — the share sheet includes AirDrop; also offers the iCloud copy-link.
    private var exportMenu: some View {
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
            Section("Share a Copy") {
                Button { showShareLink = true } label: { Label("Create Share Link…", systemImage: "link") }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Export")
    }

    /// Less-used page actions, folded into one labelled menu.
    private var moreMenu: some View {
        Menu {
            Section("Page size") {
                Button {
                    notebookVM.extendCurrentPage()
                    controller.scrollToPage(notebookVM.selectedPageIndex)
                } label: { Label("Extend Page", systemImage: "arrow.down.to.line") }
                Button {
                    notebookVM.resetCurrentPageHeight()
                } label: { Label("Reset Page Height", systemImage: "arrow.up.to.line") }
            }
            Section {
                Button { showPDFImporter = true } label: { Label("Import PDF", systemImage: "doc.badge.plus") }
                Button { showAudioNotes = true } label: { Label("Audio Notes", systemImage: "waveform") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    /// Pastes the clipboard image onto the current page as its background to
    /// annotate over. Shows a hint if the clipboard holds no image.
    private func insertPastedImage() {
        guard let image = UIPasteboard.general.image,
              let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else {
            showNoImageAlert = true
            return
        }
        if notebookVM.setBackgroundOnCurrentPage(data) {
            controller.scrollToPage(notebookVM.selectedPageIndex)
        }
    }
}
