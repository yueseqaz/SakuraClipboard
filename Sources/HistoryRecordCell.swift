import Cocoa

final class HistoryRecordCell: NSTableCellView {
    private let sourceIcon = NSImageView()
    private let thumbnail = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var thumbnailWidth: NSLayoutConstraint!
    private var labelSpacing: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        sourceIcon.imageScaling = .scaleProportionallyDown
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 3
        thumbnail.layer?.masksToBounds = true
        label.tag = 101
        label.font = NSFont.systemFont(ofSize: 13)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        timeLabel.tag = 102
        timeLabel.font = NSFont.systemFont(ofSize: 10)
        timeLabel.alignment = .right
        for subview in [sourceIcon, thumbnail, label, timeLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        thumbnailWidth = thumbnail.widthAnchor.constraint(equalToConstant: 0)
        labelSpacing = label.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor)
        NSLayoutConstraint.activate([
            sourceIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            sourceIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            sourceIcon.widthAnchor.constraint(equalToConstant: 16),
            sourceIcon.heightAnchor.constraint(equalToConstant: 16),
            thumbnail.leadingAnchor.constraint(equalTo: sourceIcon.trailingAnchor, constant: 6),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailWidth,
            thumbnail.heightAnchor.constraint(equalToConstant: 16),
            labelSpacing,
            label.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 45)
        ])
    }

    func configure(item: ClipboardItem, sourceImage: NSImage, thumbnailImage: NSImage?, title: String, isHovering: Bool) {
        sourceIcon.image = sourceImage
        let sourceName = item.sourceApp?.name ?? item.sourceApp?.bundleIdentifier
        let sourceDescription = sourceName.map { I18N.t("来源：", "Source: ") + $0 }
            ?? I18N.t("来源应用未知", "Unknown source app")
        sourceIcon.toolTip = sourceDescription
        sourceIcon.setAccessibilityLabel(sourceDescription)
        thumbnail.image = thumbnailImage
        thumbnail.isHidden = item.kind != .image
        thumbnailWidth.constant = item.kind == .image ? 16 : 0
        labelSpacing.constant = item.kind == .image ? 6 : 0
        label.stringValue = title
        label.textColor = isHovering ? .selectedMenuItemTextColor : .labelColor
        timeLabel.stringValue = I18N.relativeTime(from: item.date)
        timeLabel.textColor = isHovering ? .selectedMenuItemTextColor : .tertiaryLabelColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
