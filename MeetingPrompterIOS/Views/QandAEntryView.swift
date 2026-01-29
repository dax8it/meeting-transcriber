import SwiftUI

struct QandAEntryView: View {
    @State private var selectedSession: MeetingSession? = nil

    var body: some View {
        SessionsListView(mode: .select, titleOverride: "Q&A") { session in
            selectedSession = session
        }
        .navigationDestination(item: $selectedSession) { session in
            SessionView(session: session)
        }
    }
}

#Preview {
    NavigationStack {
        QandAEntryView()
    }
}
