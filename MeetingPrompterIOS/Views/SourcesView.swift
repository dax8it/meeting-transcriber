import SwiftUI

struct SourcesView: View {
    let sources: [DocumentChunk]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.headline)
                .foregroundColor(AppTheme.ink)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { item in
                    let idx = item.offset
                    let source = item.element
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(AppTheme.accent)
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[S\(idx + 1)] \(source.docTitle)/\(source.docType)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.ink)

                            Text(source.sectionPath)
                                .font(.caption)
                                .foregroundColor(AppTheme.mutedInk)

                            if let meetingID = source.meetingID {
                                let chunkIndex = source.chunkIndex.map(String.init) ?? "?"
                                Text("meeting \(meetingID) • chunk \(chunkIndex)")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.mutedInk)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surfaceAlt)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
