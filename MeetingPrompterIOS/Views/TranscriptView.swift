import SwiftUI

struct TranscriptView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)
                
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
                    .foregroundColor(transcriptText.isEmpty ? AppTheme.mutedInk : AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface)
            }
            .frame(height: 150)
            .scrollContentBackground(.hidden)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 0)
        .background(AppTheme.background)
    }
}
