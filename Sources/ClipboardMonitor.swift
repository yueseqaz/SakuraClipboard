import Cocoa

// MARK: - Monitor
class ClipboardMonitor {
    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var idleTicks = 0
    private let ingestQueue = DispatchQueue(label: "com.sakura.clipboard.ingest", qos: .userInitiated)

    private let fastInterval: TimeInterval = 0.2
    private let normalInterval: TimeInterval = 0.4
    private let idleInterval: TimeInterval = 0.8
    private let idleThresholdTicks = 25 // ~10s at 0.4s

    func start() {
        scheduleTimer(interval: normalInterval)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func check() {
        let pb = NSPasteboard.general
        if pb.changeCount == changeCount {
            idleTicks += 1
            if idleTicks >= idleThresholdTicks,
               abs((timer?.timeInterval ?? normalInterval) - idleInterval) > 0.001 {
                scheduleTimer(interval: idleInterval)
            }
            return
        }

        changeCount = pb.changeCount
        idleTicks = 0
        if abs((timer?.timeInterval ?? normalInterval) - fastInterval) > 0.001 {
            scheduleTimer(interval: fastInterval)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                if abs((self.timer?.timeInterval ?? self.normalInterval) - self.fastInterval) < 0.001 {
                    self.scheduleTimer(interval: self.normalInterval)
                }
            }
        }

        let imageData = pb.data(forType: .png) ?? pb.data(forType: .tiff)
        let text = pb.string(forType: .string)
        ingestQueue.async {
            if let imageData {
                ClipboardStore.shared.addImageData(imageData)
            } else if let text {
                ClipboardStore.shared.addText(text)
            }
        }
    }
}
