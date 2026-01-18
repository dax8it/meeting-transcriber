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
        VStack(spacing: 20) {
            HeaderView()
            
            if viewModel.isInitializing {
                ProgressView("Loading models...")
                    .padding()
            } else {
                TranscriptView(viewModel: viewModel)

                VStack(spacing: 8) {
                    TextField("Ask a question about this meeting...", text: $viewModel.questionText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.appState.isRecording || viewModel.appState.isTranscribing)

                    Button("Ask") {
                        viewModel.askQuestion(viewModel.questionText)
                    }
                    .disabled(
                        viewModel.appState.isRecording ||
                        viewModel.appState.isTranscribing ||
                        viewModel.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if !viewModel.answerText.isEmpty {
                    AnswerView(answerText: viewModel.answerText)
                }

                Spacer()
                
                PushToTalkButton(
                    isRecording: Binding(
                        get: { viewModel.appState.isRecording },
                        set: { _ in }
                    ),
                    onToggle: { isRecording in
                        if isRecording {
                            viewModel.startRecording()
                        } else {
                            viewModel.stopRecording()
                        }
                    }
                )
                
                StatusIndicator(status: viewModel.statusText)
            }
        }
        .padding()
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Meeting Prompter")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Tap to speak")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom)
    }
}

struct PushToTalkButton: View {
    @Binding var isRecording: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        Button(action: {
            onToggle(!isRecording)
        }) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.blue)
                    .frame(width: 120, height: 120)
                    .animation(.spring(), value: isRecording)
                
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }
        }
        .disabled(false)
    }
}

struct StatusIndicator: View {
    let status: String
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.bottom)
    }
    
    private var statusColor: Color {
        if status.contains("Loading") || status.contains("Processing") || status.contains("Generating") {
            return .orange
        } else if status.contains("Error") {
            return .red
        } else {
            return .green
        }
    }
}

#Preview {
    ContentView()
}
