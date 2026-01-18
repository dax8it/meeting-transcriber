import SwiftUI

@main
struct MeetingPrompteriOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    Task {
                        await MainViewModel.shared.initialize()
                    }
                }
        }
    }
}