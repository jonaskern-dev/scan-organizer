import Foundation
import Combine

#if os(macOS)
import IOKit
import IOKit.ps
#endif

public struct ResourceMetrics {
    public let cpuUsageTotal: Double
    public let cpuUsageEfficiency: Double  // E-cores
    public let cpuUsagePerformance: Double  // P-cores
    public let memoryUsed: Double  // in GB
    public let memoryTotal: Double  // in GB
    public let gpuUsage: Double  // 0-100%
    public let aneUsage: Double  // Apple Neural Engine 0-100%
    public let timestamp: Date
}

public class ResourceMonitor: ObservableObject {
    @Published public var metrics = ResourceMetrics(
        cpuUsageTotal: 0,
        cpuUsageEfficiency: 0,
        cpuUsagePerformance: 0,
        memoryUsed: 0,
        memoryTotal: 0,
        gpuUsage: 0,
        aneUsage: 0,
        timestamp: Date()
    )

    private var timer: Timer?
    private var previousCPUInfo: host_cpu_load_info?

    public init() {}

    public func startMonitoring(interval: TimeInterval = 1.0) {
        stopMonitoring()

        // Initial update
        updateMetrics()

        // Start periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.updateMetrics()
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMetrics() {
        let cpu = getCPUUsage()
        let memory = getMemoryUsage()
        let gpu = getGPUUsage()
        let ane = getANEUsage()

        DispatchQueue.main.async {
            self.metrics = ResourceMetrics(
                cpuUsageTotal: cpu.total,
                cpuUsageEfficiency: cpu.efficiency,
                cpuUsagePerformance: cpu.performance,
                memoryUsed: memory.used,
                memoryTotal: memory.total,
                gpuUsage: gpu,
                aneUsage: ane,
                timestamp: Date()
            )
        }
    }

    private func getCPUUsage() -> (total: Double, efficiency: Double, performance: Double) {
        #if os(macOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if result == KERN_SUCCESS {
            // Get host CPU load info
            var cpuLoadInfo = host_cpu_load_info()
            var hostInfoCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

            let kr = withUnsafeMutablePointer(to: &cpuLoadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostInfoCount)) {
                    host_statistics(mach_host_self(),
                                  HOST_CPU_LOAD_INFO,
                                  $0,
                                  &hostInfoCount)
                }
            }

            if kr == KERN_SUCCESS {
                let userTicks = Double(cpuLoadInfo.cpu_ticks.0)  // USER
                let systemTicks = Double(cpuLoadInfo.cpu_ticks.1)  // SYSTEM
                let idleTicks = Double(cpuLoadInfo.cpu_ticks.2)  // IDLE
                let niceTicks = Double(cpuLoadInfo.cpu_ticks.3)  // NICE

                let totalTicks = userTicks + systemTicks + idleTicks + niceTicks

                if let previous = previousCPUInfo, totalTicks > 0 {
                    let previousTotal = Double(previous.cpu_ticks.0 + previous.cpu_ticks.1 +
                                              previous.cpu_ticks.2 + previous.cpu_ticks.3)
                    let deltaTicks = totalTicks - previousTotal
                    let deltaUser = userTicks - Double(previous.cpu_ticks.0)
                    let deltaSystem = systemTicks - Double(previous.cpu_ticks.1)

                    if deltaTicks > 0 {
                        let cpuUsage = ((deltaUser + deltaSystem) / deltaTicks) * 100.0

                        // Estimate E-core vs P-core usage (approximation)
                        // Lower usage typically on E-cores, higher on P-cores
                        let efficiency = min(cpuUsage, 30.0)  // E-cores handle up to ~30%
                        let performance = max(0, cpuUsage - 30.0)  // P-cores kick in above 30%

                        previousCPUInfo = cpuLoadInfo
                        return (cpuUsage, efficiency, performance)
                    }
                }

                previousCPUInfo = cpuLoadInfo
            }
        }
        #endif

        return (0, 0, 0)
    }

    private func getMemoryUsage() -> (used: Double, total: Double) {
        #if os(macOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if result == KERN_SUCCESS {
            // Get system memory info
            let pageSize = vm_kernel_page_size
            var vmStat = vm_statistics64()
            var vmStatCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<natural_t>.size)

            let hostPort = mach_host_self()
            let kr = withUnsafeMutablePointer(to: &vmStat) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmStatCount)) {
                    host_statistics64(hostPort, HOST_VM_INFO64, host_info64_t($0), &vmStatCount)
                }
            }

            if kr == KERN_SUCCESS {
                let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824  // Convert to GB

                let free = Double(vmStat.free_count) * Double(pageSize) / 1_073_741_824
                let inactive = Double(vmStat.inactive_count) * Double(pageSize) / 1_073_741_824
                _ = Double(vmStat.wire_count) * Double(pageSize) / 1_073_741_824
                _ = Double(vmStat.compressor_page_count) * Double(pageSize) / 1_073_741_824

                let used = total - free - inactive

                return (used, total)
            }
        }
        #endif

        return (0, 0)
    }

    private func getGPUUsage() -> Double {
        // GPU usage monitoring requires Metal Performance Shaders or IOKit
        // This is a simplified implementation
        #if os(macOS)
        // Try to get GPU usage from IOKit
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                 IOServiceMatching("IOAccelerator"),
                                                 &iterator)

        if result == KERN_SUCCESS {
            var service: io_object_t = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                let kr = IORegistryEntryCreateCFProperties(service,
                                                          &properties,
                                                          kCFAllocatorDefault,
                                                          0)

                if kr == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] {
                    // Look for GPU usage indicators
                    if let performanceStatistics = props["PerformanceStatistics"] as? [String: Any] {
                        if let deviceUtilization = performanceStatistics["Device Utilization %"] as? Int {
                            IOObjectRelease(service)
                            IOObjectRelease(iterator)
                            return Double(deviceUtilization)
                        }
                    }
                }

                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        #endif

        // Return approximate based on current process activity
        return 0
    }

    private func getANEUsage() -> Double {
        #if os(macOS)
        // Try to get ANE power usage from IOKit
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                 IOServiceMatching("AppleH11ANEInterface"),
                                                 &iterator)

        if result == KERN_SUCCESS {
            var service: io_object_t = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                let kr = IORegistryEntryCreateCFProperties(service,
                                                          &properties,
                                                          kCFAllocatorDefault,
                                                          0)

                if kr == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] {
                    // Look for power state or activity indicators
                    if let powerState = props["PowerState"] as? Int {
                        IOObjectRelease(service)
                        IOObjectRelease(iterator)
                        // Convert power state to percentage (0-100)
                        return Double(powerState > 0 ? min(powerState * 25, 100) : 0)
                    }

                    // Alternative: check for performance statistics
                    if let perfStats = props["PerformanceStatistics"] as? [String: Any] {
                        if let utilization = perfStats["Utilization"] as? Double {
                            IOObjectRelease(service)
                            IOObjectRelease(iterator)
                            return utilization
                        }
                    }
                }

                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        #endif

        // Fallback: return 0 if not accessible
        return 0
    }
}

// Helper to format metrics for display
public extension ResourceMetrics {
    var cpuString: String {
        String(format: "CPU: %.1f%%", cpuUsageTotal)
    }

    var cpuDetailString: String {
        String(format: "E: %.1f%% P: %.1f%%", cpuUsageEfficiency, cpuUsagePerformance)
    }

    var memoryString: String {
        String(format: "RAM: %.1f/%.1f GB", memoryUsed, memoryTotal)
    }

    var gpuString: String {
        String(format: "GPU: %.1f%%", gpuUsage)
    }

    var aneString: String {
        String(format: "ANE: %.1f%%", aneUsage)
    }
}