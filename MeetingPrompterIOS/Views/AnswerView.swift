import SwiftUI

struct AnswerView: View {
    let answerText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Answer")
                .font(.headline)
            
            Text(answerText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(AppTheme.surfaceAlt)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
