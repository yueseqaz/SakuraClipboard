import Cocoa

final class MenuHoverActivation {
    private let delay: TimeInterval
    private var timer: Timer?

    init(delay: TimeInterval = 0.15) {
        self.delay = delay
    }

    func schedule(_ open: @escaping () -> Void) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            open()
        }
        self.timer = timer
        // Native menus use a nested tracking loop rather than the default run-loop mode.
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .default)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        cancel()
    }
}
