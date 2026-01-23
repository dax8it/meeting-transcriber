import SwiftUI

struct LegalDocumentView: View {
    let title: String
    let resourceName: String
    let ext: String

    @State private var text: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.red)
                } else {
                    Text(.init(text))
                        .font(.body)
                        .foregroundColor(AppTheme.ink)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        errorMessage = nil
        let candidates: [URL?] = [
            Bundle.main.url(forResource: resourceName, withExtension: ext),
            Bundle.main.url(forResource: resourceName, withExtension: ext, subdirectory: "Legal"),
            Bundle.main.url(forResource: resourceName, withExtension: ext, subdirectory: "Resources/Legal"),
        ]

        guard let url = candidates.compactMap({ $0 }).first else {
            errorMessage = "Missing document: \(resourceName).\(ext)"
            text = ""
            return
        }

        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            errorMessage = "Failed to load document: \(error.localizedDescription)"
            text = ""
        }
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(title: "Privacy", resourceName: "PRIVACY", ext: "md")
    }
}
