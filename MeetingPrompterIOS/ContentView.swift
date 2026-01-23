//
//  ContentView.swift
//  meeting-transcriber
//
//  Created by Alex Covo on 1/10/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel.shared
    
    var body: some View {
        NavigationStack {
            HomeView(viewModel: viewModel)
                .navigationDestination(item: $viewModel.activeSession) { session in
                    SessionView(session: session)
                }
        }
    }
}

#Preview {
    ContentView()
}
