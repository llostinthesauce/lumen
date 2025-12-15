import SwiftUI

public struct ModelFormatBadge: View {
    let format: ModelFormat
    
    public init(format: ModelFormat) {
        self.format = format
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: formatIcon)
                .font(.caption2)
            Text(ModelFormatDetector.formatName(format))
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(formatBackgroundColor)
        .foregroundStyle(formatForegroundColor)
        .cornerRadius(6)
    }
    
    private var formatIcon: String {
        switch format {
        case .mlx:
            return "bolt.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    private var formatBackgroundColor: Color {
        switch format {
        case .mlx:
            return Color.blue.opacity(0.15)
        case .unknown:
            return Color.gray.opacity(0.15)
        }
    }
    
    private var formatForegroundColor: Color {
        switch format {
        case .mlx:
            return .blue
        case .unknown:
            return .gray
        }
    }
}
