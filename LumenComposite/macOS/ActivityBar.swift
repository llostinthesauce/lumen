import SwiftUI

enum ActivityTab: String, CaseIterable {
    case chat = "message"
    case discovery = "magnifyingglass"
    case server = "network"
    case context = "doc.text.magnifyingglass"
    case settings = "gear"
    
    var title: String {
        switch self {
        case .chat: return "Chat"
        case .discovery: return "Discover"
        case .context: return "Context"
        case .server: return "Server"
        case .settings: return "Settings"
        }
    }
}

struct ActivityBar: View {
    @Binding var selectedTab: ActivityTab
    
    var body: some View {
        VStack(spacing: 20) {
            ForEach(ActivityTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.rawValue)
                            .font(.system(size: 20))
                    }
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(8)
                .help(tab.title)
            }
            
            Spacer()
        }
        .padding(.vertical, 20)
        .frame(width: 60)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color.primary.opacity(0.1)),
            alignment: .trailing
        )
    }
}
