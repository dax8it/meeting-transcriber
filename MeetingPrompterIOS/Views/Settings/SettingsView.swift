import SwiftUI

struct SettingsView: View {
    @State private var isShowingAIDisclosure = false
    @AppStorage("voiceQAEnabled") private var voiceQAEnabled: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("AI Disclosure")
                card {
                    Text("This app uses AI to generate transcripts, summaries, and answers. You are interacting with an AI system, not a human.")
                        .font(.body)
                        .foregroundColor(AppTheme.ink)

                    Divider().background(AppTheme.divider)

                    Button {
                        isShowingAIDisclosure = true
                    } label: {
                        HStack {
                            Text("Show disclosure again")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.accent)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }

                sectionHeader("Experimental")
                card {
                    Toggle("Voice Q&A (Push-to-Talk)", isOn: $voiceQAEnabled)
                        .font(.body)
                        .tint(AppTheme.accent)

                    Text("Enable hold-to-talk voice questions in meeting chat.")
                        .font(.caption)
                        .foregroundColor(AppTheme.mutedInk)
                }

                sectionHeader("Legal")
                card {
                    NavigationLink {
                        LegalDocumentView(title: "End User License Agreement", resourceName: "EULA", ext: "md")
                    } label: {
                        settingsRow("End User License Agreement")
                    }

                    Divider().background(AppTheme.divider)

                    NavigationLink {
                        LegalDocumentView(title: "Third-Party Notices", resourceName: "THIRD_PARTY_NOTICES", ext: "md")
                    } label: {
                        settingsRow("Third-Party Notices")
                    }

                    Divider().background(AppTheme.divider)

                    NavigationLink {
                        LegalDocumentView(title: "Privacy", resourceName: "PRIVACY", ext: "md")
                    } label: {
                        settingsRow("Privacy")
                    }
                }

                sectionHeader("About")
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meet Puppet")
                            .font(.headline)
                            .foregroundColor(AppTheme.ink)

                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.mutedInk)

                        Divider().background(AppTheme.divider)

                        Text("Uses Liquid AI LFM models under the LFM Open License v1.0.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.ink)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $isShowingAIDisclosure) {
            AIDisclosureSheetView {
                isShowingAIDisclosure = false
            }
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(AppTheme.mutedInk)
            .padding(.horizontal, 2)
    }

    private func settingsRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(AppTheme.ink)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.mutedInk)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: AppTheme.shadowSoft, radius: 10, x: 0, y: 6)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
