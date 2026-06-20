import SwiftUI

/// Feedback tab: an inset-grouped list with a short intro and a WhatsApp row
/// that opens a pre-filled chat with the support number.
struct FeedbackView: View {
    @Environment(\.openURL) private var openURL

    /// Support WhatsApp number in international format (no "+" or spaces).
    private let whatsAppNumber = "6588666375"
    /// Human-readable form shown on screen.
    private let displayNumber = "+65 8866 6375"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Send Feedback")
                            .font(.title2.bold())
                        Text("Found a bug or have an idea for a new feature? Message us on WhatsApp and we'll take a look.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("WhatsApp") {
                    Button {
                        openWhatsApp()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Message us on WhatsApp")
                                Text(displayNumber)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Feedback")
        }
    }

    /// Opens WhatsApp with a pre-filled message. Falls back to the wa.me web link
    /// if the WhatsApp app isn't installed.
    private func openWhatsApp() {
        let message = "Hi NotePad team, I'd like to share some feedback about the app:"
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let appURL = URL(string: "whatsapp://send?phone=\(whatsAppNumber)&text=\(encoded)") {
            openURL(appURL) { accepted in
                if !accepted, let webURL = URL(string: "https://wa.me/\(whatsAppNumber)?text=\(encoded)") {
                    openURL(webURL)
                }
            }
        }
    }
}
