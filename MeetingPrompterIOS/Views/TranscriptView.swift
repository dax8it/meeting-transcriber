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
            }
            .frame(height: 150)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}