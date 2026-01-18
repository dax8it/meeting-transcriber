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
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}