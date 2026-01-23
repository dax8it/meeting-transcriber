import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: MainViewModel

    @AppStorage("hasAcceptedAIDisclosure") private var hasAcceptedAIDisclosure: Bool = false
    @State private var isShowingAIDisclosure = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Meet Puppet")
                            .font(.largeTitle)
                            .fontWeight(.black)
                            .foregroundColor(AppTheme.ink)

                        Text("On-device transcription, summaries, and Q&A.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.mutedInk)
                    }

                    Spacer(minLength: 0)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .padding(.top, 8)

                VStack(spacing: 14) {
                    NavigationLink {
                        RecordView(viewModel: viewModel)
                    } label: {
                        HomeActionCard(
                            title: "New Transcription",
                            subtitle: "Record and get a live transcript",
                            systemImage: "waveform",
                            tint: AppTheme.accent
                        )
                    }

                    NavigationLink {
                        SessionsListView(mode: .browse)
                    } label: {
                        HomeActionCard(
                            title: "Summaries",
                            subtitle: "Review, share, or delete past sessions",
                            systemImage: "books.vertical",
                            tint: Color(red: 0.88, green: 0.45, blue: 0.18)
                        )
                    }

                    NavigationLink {
                        QandAEntryView()
                    } label: {
                        HomeActionCard(
                            title: "Q&A",
                            subtitle: "Ask questions with citations",
                            systemImage: "sparkle.magnifyingglass",
                            tint: Color(red: 0.75, green: 0.22, blue: 0.36)
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !hasAcceptedAIDisclosure {
                isShowingAIDisclosure = true
            }
        }
        .sheet(isPresented: $isShowingAIDisclosure) {
            AIDisclosureSheetView {
                hasAcceptedAIDisclosure = true
                isShowingAIDisclosure = false
            }
            .interactiveDismissDisabled(true)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(viewModel: MainViewModel.shared)
    }
}
