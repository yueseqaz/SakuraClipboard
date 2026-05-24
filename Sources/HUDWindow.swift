import Cocoa

final class HUDWindow {
    private static var window: NSWindow?
    private static var hideWorkItem: DispatchWorkItem?

    static func show(_ text: String) {
        hideWorkItem?.cancel()
        window?.close()

        let width: CGFloat = 120
        let height: CGFloat = 36

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.minY + 100

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let bgView = NSVisualEffectView(frame: contentView.bounds)
        bgView.material = .hudWindow
        bgView.blendingMode = .behindWindow
        bgView.state = .active
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 8
        bgView.layer?.masksToBounds = true
        contentView.addSubview(bgView)

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = contentView.bounds
        contentView.addSubview(label)

        panel.contentView = contentView
        panel.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        panel.orderFrontRegardless()
        window = panel

        let workItem = DispatchWorkItem {
            hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private static func hide() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
            self.window = nil
        })
    }
}
