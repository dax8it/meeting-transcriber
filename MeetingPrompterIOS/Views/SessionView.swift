import SwiftUI

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
                .padding(16)
                .background(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Ask a question about this meeting...", text: $viewModel.questionText)
                        .textFieldStyle(.roundedBorder)

                    Button("Ask") {
                        viewModel.ask()
                    }
                    .disabled(viewModel.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isBusy)
                }
                .padding(16)
                .background(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
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
