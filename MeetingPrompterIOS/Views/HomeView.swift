import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Meet Puppet")
                        .font(.largeTitle)
                        .fontWeight(.black)
                        .foregroundColor(AppTheme.ink)

                    Text("On-device transcription, summaries, and Q&A.")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.mutedInk)
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
    }
}

#Preview {
    NavigationStack {
        HomeView(viewModel: MainViewModel.shared)
    }
}
