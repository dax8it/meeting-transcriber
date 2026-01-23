import SwiftUI

struct TranscriptView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                
                if !viewModel.transcriptLive.isEmpty {
                    Text("(live)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            
            ScrollView {
                let transcriptText = !viewModel.transcriptLive.isEmpty ? viewModel.transcriptLive : viewModel.transcriptFinal
                Text(transcriptText.isEmpty ? "No transcript yet..." : transcriptText)
                    .font(.body)
                    .foregroundColor(transcriptText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 150)
            .padding(12)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 0)
    }
}
