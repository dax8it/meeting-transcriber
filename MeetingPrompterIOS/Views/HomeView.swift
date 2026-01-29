import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: MainViewModel

    @AppStorage("hasAcceptedAIDisclosure") private var hasAcceptedAIDisclosure: Bool = false
    @State private var isShowingAIDisclosure = false
    @State private var titleVisible = false

    @State private var recentSessions: [MeetingSession] = []
    @State private var isLoadingSessions = false
    @State private var sessionsError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Puppet")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .foregroundColor(AppTheme.ink)

                        Text("On-device transcription, summaries, and Q&A.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.mutedInk)

                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.caption)
                            Text("On-device only")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(AppTheme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surfaceAlt)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.hairline, lineWidth: 1)
                        )
                    }
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 6)
                    .animation(.easeOut(duration: 0.35), value: titleVisible)

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
                                    .stroke(AppTheme.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    NavigationLink {
                        RecordView(viewModel: viewModel)
                    } label: {
                        HomeActionCard(
                            title: "New Transcription",
                            subtitle: "Record and get a live transcript",
                            systemImage: "waveform",
                            tint: AppTheme.accent
                        )
                        .frame(minHeight: 92)
                    }

                    NavigationLink {
                        SessionsListView(mode: .browse)
                    } label: {
                        HomeActionCard(
                            title: "Summaries",
                            subtitle: "Review, share, or delete past sessions",
                            systemImage: "books.vertical",
                            tint: Color(red: 0.78, green: 0.50, blue: 0.20)
                        )
                        .frame(minHeight: 78)
                    }

                    NavigationLink {
                        QandAEntryView()
                    } label: {
                        HomeActionCard(
                            title: "Q&A",
                            subtitle: "Ask questions with citations",
                            systemImage: "sparkle.magnifyingglass",
                            tint: Color(red: 0.70, green: 0.28, blue: 0.40)
                        )
                        .frame(minHeight: 78)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Sessions")
                        .font(.headline)
                        .foregroundColor(AppTheme.ink)

                    if isLoadingSessions {
                        ProgressView("Loading...")
                            .foregroundColor(AppTheme.mutedInk)
                    } else if let sessionsError {
                        Text(sessionsError)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.mutedInk)
                    } else if recentSessions.isEmpty {
                        Text("No sessions yet. Start a transcription to see it here.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.mutedInk)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(recentSessions) { session in
                                NavigationLink {
                                    SessionView(session: session)
                                } label: {
                                    RecentSessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
                .background(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
        .background(homeBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !hasAcceptedAIDisclosure {
                isShowingAIDisclosure = true
            }
            if !titleVisible {
                titleVisible = true
            }
        }
        .task {
            await loadRecentSessions()
        }
        .sheet(isPresented: $isShowingAIDisclosure) {
            AIDisclosureSheetView {
                hasAcceptedAIDisclosure = true
                isShowingAIDisclosure = false
            }
            .interactiveDismissDisabled(true)
        }
    }

    private var homeBackground: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.background, AppTheme.backgroundElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.accent.opacity(0.18), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
    }

    @MainActor
    private func loadRecentSessions() async {
        isLoadingSessions = true
        sessionsError = nil
        defer { isLoadingSessions = false }

        do {
            let list = try await FileStore.shared.listSessions()
            recentSessions = Array(list.prefix(3))
        } catch {
            recentSessions = []
            sessionsError = "Unable to load recent sessions."
        }
    }
}

private struct RecentSessionRow: View {
    let session: MeetingSession

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.ink)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundColor(AppTheme.mutedInk)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.mutedInk)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(AppTheme.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var titleText: String {
        let cal = Calendar.current
        let time = Self.timeFormatter.string(from: session.createdAt)
        if cal.isDateInToday(session.createdAt) {
            return "Today, \(time)"
        }
        if cal.isDateInYesterday(session.createdAt) {
            return "Yesterday, \(time)"
        }
        return Self.dateFormatter.string(from: session.createdAt)
    }

    private var subtitleText: String {
        if let dur = session.durationSeconds, dur > 1 {
            return "Session - \(formatDuration(dur))"
        }
        return "Session - Summary + Q&A"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        if m > 0 {
            return String(format: "%dm %02ds", m, r)
        }
        return "\(r)s"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

#Preview {
    NavigationStack {
        HomeView(viewModel: MainViewModel.shared)
    }
}
