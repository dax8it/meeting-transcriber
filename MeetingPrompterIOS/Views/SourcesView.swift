import SwiftUI

struct SourcesView: View {
    let sources: [DocumentChunk]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sources) { source in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text(source.sectionPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}