import SwiftUI
import Foundation
import Combine

struct RamUsageView: View {
    @State private var usedMemory: Double = 0
    @State private var totalMemory: Double = 0
    @State private var memoryPressure: Double = 0
    
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            // Progress Bar
            GeometryReader { geometry in
                let safeTotal = max(totalMemory, 0.001)
                let ratio = min(max(usedMemory / safeTotal, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    
                    Capsule()
                        .fill(usageColor)
                        .frame(width: geometry.size.width * CGFloat(ratio))
                        .animation(.easeInOut, value: usedMemory)
                }
            }
            .frame(width: 60, height: 6)
            
            // Text Stats
            Text(String(format: "%.1f / %.0f GB", usedMemory, totalMemory))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .onReceive(timer) { _ in
            updateMemoryStats()
        }
        .onAppear {
            updateMemoryStats()
        }
    }
    
    private var usageColor: Color {
        let denominator = max(totalMemory, 0.001)
        let percentage = usedMemory / denominator
        if percentage > 0.85 {
            return .red
        } else if percentage > 0.7 {
            return .orange
        } else {
            return .green
        }
    }
    
    private func updateMemoryStats() {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0 // GB
        self.totalMemory = total
        
        // Get used memory (System-wide approximation)
        // On macOS sandbox, getting exact system used memory is hard.
        // We will use os_proc_available_memory() if available or estimate via Mach host stats.
        
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let active = Double(stats.active_count) * pageSize
            let wired = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            
            // Approximate "Used" = Active + Wired + Compressed
            // This is a rough metric for "Memory Pressure"
            let usedBytes = active + wired + compressed
            self.usedMemory = usedBytes / 1_073_741_824.0
        } else {
            // Fallback
            self.usedMemory = 0
        }
    }
}
