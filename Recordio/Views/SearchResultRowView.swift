import SwiftUI
import Foundation

struct SearchResultRowView: View {
    let result: SearchService.SearchResult
    
    var body: some View {
        HStack(spacing: 0) {
            // Accent bar based on match type
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(result.recording.title ?? "Untitled")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    matchTypeBadge
                }
                
                if !result.contextSnippet.isEmpty {
                    Text(result.contextSnippet)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }
                
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(formatDuration(result.recording.duration))
                        .font(.caption)
                    
                    Spacer()
                    
                    Text((result.recording.createdAt ?? Date()), style: .relative)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
    
    private var gradientColors: [Color] {
        switch result.matchType {
        case .title: return [.blue, .purple]
        case .transcript: return [.orange, .yellow]
        case .tag: return [.green, .mint]
        }
    }
    
    private var matchTypeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: matchIcon)
                .font(.caption2)
            Text(matchText)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(gradientColors[0].opacity(0.1))
        .foregroundColor(gradientColors[0])
        .cornerRadius(4)
    }
    
    private var matchIcon: String {
        switch result.matchType {
        case .title: return "doc.text.fill"
        case .transcript: return "text.quote"
        case .tag: return "tag.fill"
        }
    }
    
    private var matchText: String {
        switch result.matchType {
        case .title: return "Title"
        case .transcript: return "Transcript"
        case .tag: return "Tag"
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
