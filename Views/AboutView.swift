import SwiftUI

/// About tab: an inset-grouped list with a description card, the developer and
/// website, a note on sync, and the running version.
struct AboutView: View {
    private let websiteURL = URL(string: "https://www.tertiaryinfotech.com")!

    /// Marketing version + build without the leading "v", e.g. "1.4 (14)".
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NotePad")
                            .font(.title2.bold())
                        Text("NotePad is a natural handwriting notebook for Apple Pencil. Write notes, sketch diagrams and flowcharts, import PDFs, and organize everything into nested notebooks.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Developer") {
                    Label {
                        Text("Tertiary Infotech Academy Pte Ltd")
                    } icon: {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(.tint)
                    }
                    Link(destination: websiteURL) {
                        Label {
                            Text("tertiaryinfotech.com")
                        } icon: {
                            Image(systemName: "globe")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                Section("Sync") {
                    Text("Your notebooks sync securely through your private iCloud. Nothing is stored on our servers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Self.versionString)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("About")
        }
    }
}
