import AppKit
import MeetingCountdownCore

/// A meeting's row in the menu: the title, "In 23 min • 3:30 PM • Work" under it, and a Join button
/// on the right when the invite has a call link. It's a custom view because a standard menu item
/// can't hold a second click target. A click anywhere else runs the item's own action.
/// The next meeting gets an accent bar to the left of its text.
final class MeetingMenuRowView: NSView {
    let meeting: Meeting
    private let calendarName: String?
    private let isNext: Bool
    private let onJoin: () -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private lazy var text = NSStackView(views: [titleLabel, subtitleLabel])

    /// Matches where a standard menu item's title starts when no item in the menu has an image.
    private static let horizontalInset: CGFloat = 16
    private static let accentWidth: CGFloat = 2
    private static let accentGap: CGFloat = 8
    /// How much shorter the bar is than the text, at each end.
    private static let accentInset: CGFloat = 4
    /// The blue of the app icon's badge.
    private static let accentColor = NSColor(srgbRed: 0x55 / 255, green: 0x96 / 255, blue: 0xD3 / 255, alpha: 1)
    private static let maxTextWidth: CGFloat = 320

    init(meeting: Meeting, calendarName: String?, isNext: Bool, joinHelp: String?, onJoin: @escaping () -> Void) {
        self.meeting = meeting
        self.calendarName = calendarName
        self.isNext = isNext
        self.onJoin = onJoin
        super.init(frame: .zero)

        titleLabel.stringValue = meeting.title
        titleLabel.font = .menuFont(ofSize: 0)
        subtitleLabel.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for label in [titleLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxTextWidth).isActive = true
        }

        let row = NSStackView()
        row.addView(text, in: .leading)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        // Every row leaves room for the accent bar, so the titles line up whichever row has it.
        let leading = Self.horizontalInset + Self.accentWidth + Self.accentGap
        row.edgeInsets = NSEdgeInsets(top: 4, left: leading, bottom: 5, right: Self.horizontalInset)
        if let joinHelp {
            let join = NSButton(title: "Join", target: self, action: #selector(join))
            join.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)
            join.imagePosition = .imageLeading
            join.controlSize = .small
            join.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            join.toolTip = joinHelp
            join.setAccessibilityLabel(joinHelp)
            if !isNext {
                // A bordered button ignores `contentTintColor`, so the title and camera get the color.
                let gray = NSColor.secondaryLabelColor
                join.attributedTitle = NSAttributedString(
                    string: join.title, attributes: [.font: join.font as Any, .foregroundColor: gray])
                join.image = join.image?.withSymbolConfiguration(.init(paletteColors: [gray]))
            }
            row.addView(join, in: .trailing)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        update(now: Date())
        // The menu stretches every item's view to its widest one.
        frame.size = fittingSize
        autoresizingMask = .width
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A section header in the primary text color, rather than a standard header's gray, lined up
    /// with the standard ones. A section header ignores the font and color of an attributed title,
    /// so this takes a view.
    static func header(_ title: String, bold: Bool) -> NSMenuItem {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: bold ? .bold : .regular)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -horizontalInset),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -3),
        ])
        view.frame.size = view.fittingSize
        view.autoresizingMask = .width
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = view
        item.isEnabled = false
        return item
    }

    private var subtitle = ""
    private var countdownLength = 0

    /// Called on each tick, so the countdown stays current while the menu is open.
    func update(now: Date) {
        subtitle = MenuBarSummary.menuSubtitle(for: meeting, now: now, calendarName: calendarName)
        countdownLength = (MenuBarSummary.countdown(for: meeting, now: now) as NSString).length
        styleText()
    }

    /// The next meeting's title and countdown are in the primary text color; everything else, and
    /// every other row (Join button included), is gray. A highlighted row is all in the highlight's
    /// text color.
    private func styleText() {
        let highlighted = isHighlighted
        let secondary: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        titleLabel.textColor = highlighted ? .selectedMenuItemTextColor : isNext ? .labelColor : secondary
        let size = NSFont.smallSystemFontSize
        let text = NSMutableAttributedString(
            string: subtitle, attributes: [.font: NSFont.menuFont(ofSize: size), .foregroundColor: secondary])
        let countdown = NSRange(location: 0, length: countdownLength)
        if isNext, !highlighted {
            text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: countdown)
        }
        if !subtitleLabel.attributedStringValue.isEqual(to: text) {
            subtitleLabel.attributedStringValue = text
        }
    }

    // MARK: - Highlight and clicks

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    override func viewWillDraw() {
        super.viewWillDraw()
        styleText()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 6, yRadius: 6).fill()
        }
        if isNext {
            (isHighlighted ? NSColor.selectedMenuItemTextColor : Self.accentColor).setFill()
            let bar = NSRect(
                x: Self.horizontalInset, y: text.frame.minY, width: Self.accentWidth, height: text.frame.height
            ).insetBy(dx: 0, dy: Self.accentInset)
            NSBezierPath(roundedRect: bar, xRadius: Self.accentWidth / 2, yRadius: Self.accentWidth / 2).fill()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }

    @objc private func join() {
        enclosingMenuItem?.menu?.cancelTracking()
        onJoin()
    }
}
