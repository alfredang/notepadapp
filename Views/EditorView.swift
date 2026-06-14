import SwiftUI

/// The drawing surface: the page canvas with a floating toolbar and zoom controls.
struct EditorView: View {
    let pages: [Page]
    @Bindable var editor: EditorViewModel
    let autoSave: AutoSaveService
    let controller: CanvasController
    let structureToken: Int

    private let zoomPresets: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0]

    var body: some View {
        VStack(spacing: 0) {
            // The drawing toolbar only appears on the editing device (iPad);
            // iPhone / Mac are view-only (scroll, zoom, page-jump).
            if editor.isEditable && !editor.isPaletteHidden {
                ToolbarView(editor: editor, controller: controller)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack(alignment: .bottomLeading) {
                CanvasContainerView(
                    pages: pages,
                    editor: editor,
                    autoSave: autoSave,
                    structureToken: structureToken,
                    toolStateToken: editor.toolStateToken,
                    controller: controller
                )
                .ignoresSafeArea(edges: .bottom)

                zoomControls
                    .padding(16)

                if pages.count > 1 {
                    pageJumpButtons
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: editor.isPaletteHidden)
        // Push tool/color/width changes to the canvas the instant they change.
        .onChange(of: editor.toolStateToken) { _, _ in controller.applyTool() }
    }

    /// Jumps straight to the first / last page of the notebook.
    private var pageJumpButtons: some View {
        VStack(spacing: 10) {
            jumpButton(systemImage: "chevron.up", label: "Jump to first page") {
                controller.scrollToPage(0)
            }
            jumpButton(systemImage: "chevron.down", label: "Jump to last page") {
                controller.scrollToPage(pages.count - 1)
            }
        }
    }

    private func jumpButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .softShadow()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel(label)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button {
                controller.setZoom(max(0.25, editor.zoomScale - 0.25))
            } label: { Image(systemName: "minus.magnifyingglass") }

            Menu("\(Int(editor.zoomScale * 100))%") {
                ForEach(zoomPresets, id: \.self) { preset in
                    Button("\(Int(preset * 100))%") { controller.setZoom(preset) }
                }
            }
            .frame(width: 64)

            Button {
                controller.setZoom(min(5.0, editor.zoomScale + 0.25))
            } label: { Image(systemName: "plus.magnifyingglass") }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .softShadow()
    }
}
