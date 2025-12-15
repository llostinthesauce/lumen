import SwiftUI
import Combine

struct TelemetryHUD: View {
    @ObservedObject var state: AppState
    @Binding var isVisible: Bool
    @State private var stats: TelemetryStats = .placeholder
    @State private var timerCancellable: AnyCancellable?
    @AppStorage("telemetry.sampling.seconds") private var sampling: Double = 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Telemetry")
                    .font(.headline)
                Spacer()
                Button {
                    isVisible = false
                    TelemetrySettings.shared.hudEnabled = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], alignment: .leading, spacing: 10) {
                MetricView(title: "Model", value: currentModelLabel, accent: .blue)
                MetricView(title: "Tokens/s", value: stats.tps, accent: .green)
                MetricView(title: "RAM", value: stats.ramUsage, accent: .orange)
                MetricView(title: "VRAM", value: stats.vramUsage, accent: .purple)
                MetricView(title: "Temp", value: stats.thermalState, accent: .red)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
        .frame(maxWidth: 320)
        .onAppear { start() }
        .onDisappear { stop() }
    }
    
    private var currentModelLabel: String {
        if let url = state.currentModelURL, state.isModelLoaded {
            return url.lastPathComponent
        }
        return "None"
    }
    
    private func start() {
        timerCancellable = Timer.publish(every: sampling, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task { @MainActor in
                    stats = TelemetryStats.capture(state: state)
                }
            }
        Task { @MainActor in
            stats = TelemetryStats.capture(state: state)
        }
    }
    
    private func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

private struct MetricView: View {
    let title: String
    let value: String
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct TelemetryStats {
    let tps: String
    let ramUsage: String
    let vramUsage: String
    let thermalState: String
    
    static var placeholder: TelemetryStats {
        TelemetryStats(tps: "--", ramUsage: "--", vramUsage: "--", thermalState: "--")
    }
    
    static func capture(state: AppState) -> TelemetryStats {
        let ram = Self.memoryUsage()
        let vram = Self.vramUsage()
        let thermal = Self.thermal()
        let tps = Self.tokensPerSecond(state: state)
        return TelemetryStats(tps: tps, ramUsage: ram, vramUsage: vram, thermalState: thermal)
    }
    
    private static func memoryUsage() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let used = Int64(info.phys_footprint)
            return humanReadable(used)
        }
        return "--"
    }
    
    private static func vramUsage() -> String {
        // macOS unified memory; GPU-specific usage not directly exposed without Metal counters.
        // Show placeholder to avoid misleading numbers.
        return "n/a"
    }
    
    private static func tokensPerSecond(state: AppState) -> String {
        if let tps = state.lastTokensPerSecond, tps.isFinite {
            return String(format: "%.2f", tps)
        }
        return "--"
    }
    
    private static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

private func humanReadable(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var idx = 0
    while value >= 1024 && idx < units.count - 1 {
        value /= 1024
        idx += 1
    }
    return String(format: "%.1f %@", value, units[idx])
}
