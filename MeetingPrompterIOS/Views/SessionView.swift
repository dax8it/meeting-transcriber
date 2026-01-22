import SwiftUI
import UIKit

struct SessionView: View {
    @StateObject private var viewModel: SessionViewModel
    @State private var isShowingShare = false

    init(session: MeetingSession) {
        _viewModel = StateObject(wrappedValue: SessionViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)

                    Text(viewModel.summaryText.isEmpty ? "Generating..." : viewModel.summaryText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    HStack {
                        Button {
                            isShowingShare = true
                        } label: {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                        }
                        .disabled(!viewModel.summaryReady || viewModel.shareURL == nil)

                        Spacer()

                        Button("Reload") {
                            Task { await viewModel.reloadArtifacts() }
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Ask a question about this meeting...", text: $viewModel.questionText)
                        .textFieldStyle(.roundedBorder)

                    Button("Ask") {
                        viewModel.ask()
                    }
                    .disabled(viewModel.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isBusy)
                }
                .padding(.horizontal)

                if viewModel.isBusy {
                    ProgressView("Answering...")
                        .padding(.horizontal)
                }

                if !viewModel.answerText.isEmpty {
                    AnswerView(answerText: viewModel.answerText)
                }

                if !viewModel.sources.isEmpty {
                    SourcesView(sources: viewModel.sources)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.reloadArtifacts()
        }
        .sheet(isPresented: $isShowingShare) {
            if let url = viewModel.shareURL {
                ShareSheet(activityItems: [url])
            } else {
                ShareSheet(activityItems: [])
            }
        }
    }
}
