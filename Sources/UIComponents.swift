import Cocoa

// MARK: - Design Tokens
struct DS {
    static let accent      = NSColor(red: 0.16, green: 0.49, blue: 0.95, alpha: 1)
    static let accentSoft  = NSColor(red: 0.16, green: 0.49, blue: 0.95, alpha: 0.14)
    static let bg          = NSColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 1)
    static let surface     = NSColor.white
    static let surfaceHov  = NSColor(red: 0.94, green: 0.97, blue: 1.00, alpha: 1)
    static let border      = NSColor(red: 0.84, green: 0.88, blue: 0.95, alpha: 1)
    static let textPrimary = NSColor(red: 0.14, green: 0.16, blue: 0.21, alpha: 1)
    static let textSec     = NSColor(red: 0.42, green: 0.47, blue: 0.55, alpha: 1)
    static let danger      = NSColor(red: 0.88, green: 0.29, blue: 0.25, alpha: 1)
    static let success     = NSColor(red: 0.18, green: 0.64, blue: 0.38, alpha: 1)
    static let favorite    = NSColor(red: 0.94, green: 0.66, blue: 0.16, alpha: 1)

    static let radius: CGFloat = 10
    static let radiusSm: CGFloat = 6
    static let fontMono  = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let fontLabel = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let fontSmall = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let fontTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
}

// MARK: - Pill Badge
class BadgeView: NSView {
    let label = NSTextField(labelWithString: "")

    init(_ text: String, color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor

        label.stringValue = text
        label.font = DS.fontSmall
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalTo: label.widthAnchor, constant: 10),
            heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Hover Preview Image
class HoverPreviewImageView: NSImageView {
    private let previewPopover = NSPopover()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        previewPopover.behavior = .semitransient
        previewPopover.animates = true
        previewPopover.appearance = NSAppearance(named: .aqua)

        let ta = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(ta)
    }

    override func mouseEntered(with event: NSEvent) {
        showPreview()
    }

    override func mouseExited(with event: NSEvent) {
        previewPopover.performClose(nil)
    }

    private func showPreview() {
        guard let image, !previewPopover.isShown else { return }
        let vc = NSViewController()

        let preview = NSImageView(image: image)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.masksToBounds = true

        let size = previewSize(for: image)
        preview.frame = NSRect(origin: .zero, size: size)
        vc.view = preview
        previewPopover.contentViewController = vc
        previewPopover.contentSize = size
        previewPopover.show(relativeTo: bounds, of: self, preferredEdge: .maxX)
    }

    private func previewSize(for image: NSImage) -> NSSize {
        let maxW: CGFloat = 360
        let maxH: CGFloat = 260
        let src = image.size
        guard src.width > 0, src.height > 0 else { return NSSize(width: maxW, height: maxH) }
        let scale = min(maxW / src.width, maxH / src.height, 1)
        return NSSize(width: floor(src.width * scale), height: floor(src.height * scale))
    }
}

// MARK: - Clipboard Row View
class ClipRowView: NSView {
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    let item: ClipboardItem
    var onCopy: ((ClipboardItem) -> Void)?
    var onToggleFavorite: ((ClipboardItem) -> Void)?
    var onRequestFullText: ((ClipboardItem) -> String?)?
    var onRequestImage: ((ClipboardItem) -> NSImage?)?
    var onExpandChanged: ((ClipRowView, Bool) -> Void)?

    private let bgLayer = CALayer()
    private var textLabel: NSTextField?
    private var textMetaLabel: NSTextField?
    private var expandButton: NSButton?
    private var imageView: HoverPreviewImageView?
    private var isExpandedText = false
    private var hasLoadedFullText = false
    private let collapsedTextLines = 2
    private let expandedTextLines = 0

    init(item: ClipboardItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        setupLayer()
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayer() {
        bgLayer.cornerRadius = DS.radius
        bgLayer.backgroundColor = DS.surface.cgColor
        bgLayer.borderWidth = 1
        bgLayer.borderColor = DS.border.cgColor
        layer?.addSublayer(bgLayer)
    }

    override func layout() {
        super.layout()
        bgLayer.frame = bounds
    }

    private func setupContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 6

        if item.text != nil {
            header.addArrangedSubview(BadgeView("TEXT", color: DS.accent))
        } else {
            header.addArrangedSubview(BadgeView("IMAGE", color: DS.success))
        }
        if item.isFavorite {
            header.addArrangedSubview(BadgeView(I18N.t("收藏", "FAV"), color: DS.favorite))
        }

        let dateLabel = NSTextField(labelWithString: Self.timeFormatter.string(from: item.date))
        dateLabel.font = DS.fontSmall
        dateLabel.textColor = DS.textSec
        header.addArrangedSubview(dateLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(spacer)

        let copyHint = NSTextField(labelWithString: I18N.t("⌘ 点击复制", "⌘ Click to Copy"))
        copyHint.font = DS.fontSmall
        copyHint.textColor = DS.textSec.withAlphaComponent(0.5)
        header.addArrangedSubview(copyHint)

        let favBtn = NSButton(title: item.isFavorite ? "★" : "☆", target: self, action: #selector(toggleFavorite))
        favBtn.bezelStyle = .inline
        favBtn.isBordered = false
        favBtn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        favBtn.contentTintColor = item.isFavorite ? DS.favorite : DS.textSec
        favBtn.toolTip = item.isFavorite ? I18N.t("取消收藏", "Unfavorite") : I18N.t("收藏", "Favorite")
        header.addArrangedSubview(favBtn)

        stack.addArrangedSubview(header)

        if let text = item.text {
            let label = NSTextField(labelWithString: text)
            label.font = DS.fontMono
            label.textColor = DS.textPrimary
            label.lineBreakMode = .byCharWrapping
            label.maximumNumberOfLines = collapsedTextLines
            label.cell?.wraps = true
            label.cell?.truncatesLastVisibleLine = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
            textLabel = label

            let newlineCount = text.reduce(0) { $1.isNewline ? $0 + 1 : $0 }
            let measuredLength = max(item.textLength, text.count)
            let isLongText = measuredLength > 60 || item.hasMoreText || newlineCount >= 1
            if isLongText {
                let meta = NSTextField(labelWithString: I18N.t("已自动折叠 · \(measuredLength) 字符", "Collapsed · \(measuredLength) chars"))
                meta.font = DS.fontSmall
                meta.textColor = DS.textSec.withAlphaComponent(0.75)
                stack.addArrangedSubview(meta)
                textMetaLabel = meta

                let expandBtn = NSButton(title: I18N.t("展开", "Expand"), target: self, action: #selector(toggleTextExpand))
                expandBtn.bezelStyle = .inline
                expandBtn.isBordered = false
                expandBtn.font = DS.fontSmall
                expandBtn.contentTintColor = DS.accent
                expandBtn.alignment = .left
                expandBtn.setContentHuggingPriority(.required, for: .horizontal)
                stack.addArrangedSubview(expandBtn)
                expandButton = expandBtn
            }
        }

        if let img = item.image {
            let iv = HoverPreviewImageView(image: img)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = DS.radiusSm
            iv.layer?.masksToBounds = true
            iv.heightAnchor.constraint(equalToConstant: 100).isActive = true
            stack.addArrangedSubview(iv)
            imageView = iv
        } else if item.kind == .image {
            let iv = HoverPreviewImageView(frame: .zero)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = DS.radiusSm
            iv.layer?.masksToBounds = true
            iv.heightAnchor.constraint(equalToConstant: 100).isActive = true
            stack.addArrangedSubview(iv)
            imageView = iv
        }
    }

    func hydrateDeferredContent() {
        if item.kind == .image, imageView?.image == nil, let img = onRequestImage?(item) {
            imageView?.image = img
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas {
            removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(ta)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            bgLayer.backgroundColor = DS.surfaceHov.cgColor
            bgLayer.borderColor = DS.accent.withAlphaComponent(0.3).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            bgLayer.backgroundColor = DS.surface.cgColor
            bgLayer.borderColor = DS.border.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if shouldPassThroughClick(at: localPoint) {
            super.mouseDown(with: event)
            return
        }
        onCopy?(item)
        flashCopied()
    }

    private func shouldPassThroughClick(at point: NSPoint) -> Bool {
        guard let hit = hitTest(point) else { return false }
        if hit is NSButton || hit is NSControl {
            return true
        }
        return false
    }

    @objc private func toggleTextExpand() {
        isExpandedText.toggle()
        applyExpandedState(notify: true)
    }

    func collapseTextIfNeeded() {
        guard isExpandedText else { return }
        isExpandedText = false
        applyExpandedState(notify: false)
    }

    private func applyExpandedState(notify: Bool) {
        guard let label = textLabel else { return }

        if isExpandedText, item.hasMoreText, !hasLoadedFullText,
           let full = onRequestFullText?(item), !full.isEmpty {
            label.stringValue = full
            hasLoadedFullText = true
        }

        label.maximumNumberOfLines = isExpandedText ? expandedTextLines : collapsedTextLines
        label.cell?.truncatesLastVisibleLine = !isExpandedText
        expandButton?.title = isExpandedText ? I18N.t("收起", "Collapse") : I18N.t("展开", "Expand")

        if let meta = textMetaLabel {
            let count = max(item.textLength, label.stringValue.count)
            meta.stringValue = isExpandedText
                ? I18N.t("完整内容预览中 · \(count) 字符", "Full preview · \(count) chars")
                : I18N.t("已自动折叠 · \(count) 字符", "Collapsed · \(count) chars")
        }

        if notify {
            onExpandChanged?(self, isExpandedText)
        }

        needsLayout = true
        superview?.layoutSubtreeIfNeeded()
    }

    @objc private func toggleFavorite() {
        onToggleFavorite?(item)
    }

    private func flashCopied() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            bgLayer.backgroundColor = DS.accentSoft.cgColor
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.bgLayer.backgroundColor = DS.surface.cgColor
            }
        })
    }
}

// MARK: - Toggle Switch
class ToggleSwitch: NSControl {
    var isOn: Bool = false {
        didSet { updateAppearance(animated: true) }
    }
    var onToggle: ((Bool) -> Void)?

    private let track = CALayer()
    private let thumb = CALayer()

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 20))
        wantsLayer = true
        setupLayers()
        updateAppearance(animated: false)

        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        track.cornerRadius = 10
        track.frame = CGRect(x: 0, y: 0, width: 36, height: 20)
        layer?.addSublayer(track)

        thumb.cornerRadius = 8
        thumb.backgroundColor = NSColor.white.cgColor
        thumb.shadowColor = NSColor.black.cgColor
        thumb.shadowOpacity = 0.25
        thumb.shadowOffset = CGSize(width: 0, height: -1)
        thumb.shadowRadius = 2
        layer?.addSublayer(thumb)
    }

    private func updateAppearance(animated: Bool) {
        let thumbX: CGFloat = isOn ? 18 : 2
        let trackColor = isOn ? DS.accent.cgColor : NSColor(white: 0.35, alpha: 1).cgColor
        let thumbFrame = CGRect(x: thumbX, y: 2, width: 16, height: 16)

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            track.backgroundColor = trackColor
            thumb.frame = thumbFrame
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.disableActions()
            track.backgroundColor = trackColor
            thumb.frame = thumbFrame
            CATransaction.commit()
        }
    }

    @objc private func tapped() {
        isOn.toggle()
        onToggle?(isOn)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 20) }
}
