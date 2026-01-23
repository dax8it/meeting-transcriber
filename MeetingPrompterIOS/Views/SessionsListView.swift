import SwiftUI

struct SessionsListView: View {
    enum Mode {
        case browse
        case select
    }

    let mode: Mode
    var titleOverride: String? = nil
    var onSelect: ((MeetingSession) -> Void)? = nil

    @State private var sessions: [MeetingSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    @State private var pendingDeleteSession: MeetingSession? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sessions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView("Couldn't load sessions", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "sparkles", description: Text("Record a meeting to see it here."))
            } else {
                List {
                    ForEach(sessions) { session in
                        row(for: session)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(AppTheme.background)
                    }
                    .onDelete(perform: delete)
                    .deleteDisabled(mode != .browse)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(titleOverride ?? (mode == .browse ? "Summaries" : "Pick a Session"))
        .navigationBarTitleDisplayMode(.inline)
        .background(AppTheme.background.ignoresSafeArea())
        .task { await loadSessions() }
        .refreshable { await loadSessions() }
        .confirmationDialog(
            "Delete this meeting? This cannot be undone.",
            isPresented: Binding(
                get: { pendingDeleteSession != nil },
                set: { newValue in
                    if !newValue { pendingDeleteSession = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let session = pendingDeleteSession else { return }
                pendingDeleteSession = nil
                performDelete(session)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSession = nil
            }
        }
    }

    @ViewBuilder
    private func row(for session: MeetingSession) -> some View {
        switch mode {
        case .browse:
            NavigationLink {
                SessionView(session: session)
            } label: {
                SessionRow(session: session)
            }

        case .select:
            Button {
                onSelect?(session)
            } label: {
                SessionRow(session: session)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadSessions() async {
        isLoading = true
        errorMessage = nil

        do {
            let list = try await FileStore.shared.listSessions()
            sessions = list
            isLoading = false
        } catch {
            sessions = []
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func delete(at offsets: IndexSet) {
        guard mode == .browse else { return }
        guard let first = offsets.first, sessions.indices.contains(first) else { return }
        pendingDeleteSession = sessions[first]
    }

    private func performDelete(_ session: MeetingSession) {
        sessions.removeAll { $0.id == session.id }

        Task {
            do {
                try await FileStore.shared.deleteSession(session)
            } catch {
                await loadSessions()
            }
        }
    }
}

private struct SessionRow: View {
    let session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(titleText)
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.mutedInk)
            }

            Text(subtitleText)
                .font(.subheadline)
                .foregroundColor(AppTheme.mutedInk)
                .lineLimit(2)
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
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
            return "Session \u{2022} \(formatDuration(dur))"
        }
        return "Session \u{2022} Summary + Q&A"
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
        SessionsListView(mode: .browse)
    }
}
