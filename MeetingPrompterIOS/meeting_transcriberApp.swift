//
//  meeting_transcriberApp.swift
//  meeting-transcriber
//
//  Created by Alex Covo on 1/10/26.
//

import SwiftUI

@main
struct meeting_transcriberApp: App {
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
