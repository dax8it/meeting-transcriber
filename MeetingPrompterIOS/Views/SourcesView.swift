import SwiftUI

struct SourcesView: View {
    let sources: [DocumentChunk]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { item in
                    let idx = item.offset
                    let source = item.element
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[S\(idx + 1)] \(source.docTitle)/\(source.docType)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text(source.sectionPath)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let meetingID = source.meetingID {
                                let chunkIndex = source.chunkIndex.map(String.init) ?? "?"
                                Text("meeting \(meetingID) • chunk \(chunkIndex)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
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
