import Foundation
import IOKit.ps

/// Reports whether the Mac is running on battery, and tells you when that changes.
final class PowerMonitor {
    var onChange: (() -> Void)?
    private var source: CFRunLoopSource?

    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    init() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }, ctx)?.takeRetainedValue() {
            source = s
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
        }
    }

    deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) } }
}
