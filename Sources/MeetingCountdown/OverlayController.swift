import AppKit
import MeetingCountdownCore
import Observation
import SwiftUI

@MainActor
@Observable
final class OverlayModel {
    var title = ""
    var remaining = ""
    /// Tooltip for the Join button, e.g. "Join Google Meet"; nil hides the button.
    var joinHelp: String?
    var onJoin: () -> Void = {}
    /// Bumped each time the panel appears, to replay the attention shimmer.
    var introCount = 0
}

/// Animated values for the brief shimmer + glow that plays when the overlay appears.
private struct IntroEffect {
    /// Position of the light sweep, in card widths: -1 is fully off the left edge, 1 fully off the right.
    var sweep: CGFloat = -1
    var glow: Double = 0
}

private struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.remaining)
                    .font(.system(size: 28, weight: .semibold).monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let help = model.joinHelp {
                JoinButton(help: help, action: model.onJoin)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 240, alignment: .leading)
        .background(.regularMaterial, in: Self.shape)
        .keyframeAnimator(initialValue: IntroEffect(), trigger: model.introCount) { [reduceMotion] content, effect in
            content.overlay { Self.introOverlay(effect, reduceMotion: reduceMotion) }
        } keyframes: { _ in
            KeyframeTrack(\.sweep) {
                LinearKeyframe(-1, duration: AttentionView.landingTime)
                CubicKeyframe(1, duration: 0.9)
            }
            KeyframeTrack(\.glow) {
                LinearKeyframe(0, duration: AttentionView.landingTime - 0.15)
                CubicKeyframe(1, duration: 0.25)
                CubicKeyframe(1, duration: 0.15)
                CubicKeyframe(0, duration: 0.7)
            }
        }
    }

    private nonisolated static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    private nonisolated static func introOverlay(_ effect: IntroEffect, reduceMotion: Bool) -> some View {
        ZStack {
            if !reduceMotion {
                GeometryReader { geo in
                    let band = geo.size.width * 0.45
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band, height: geo.size.height * 3)
                    .rotationEffect(.degrees(20))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .offset(x: effect.sweep * (geo.size.width + band) / 2 * 1.2)
                    .blendMode(.plusLighter)
                }
            }
            // A soft inner halo plus a crisp rim, both in the accent color.
            shape.strokeBorder(Color.accentColor, lineWidth: 6)
                .blur(radius: 6)
                .opacity(effect.glow * 0.6)
            shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                .opacity(effect.glow)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// Glowing rings that start far outside the card and get pulled into it, drawn in a larger
/// click-through window behind the overlay. `inset` is the gap between this view's edge and the card's.
private struct AttentionView: View {
    nonisolated static let ringCount = 3
    nonisolated static let ringStagger: TimeInterval = 0.12
    nonisolated static let ringDuration: TimeInterval = 0.75
    /// When the first ring reaches the card; the card's own glow is timed to this.
    static let landingTime: TimeInterval = 0.7
    static let totalDuration = ringDuration + ringStagger * Double(ringCount - 1)

    let start: Date
    let inset: CGFloat

    var body: some View {
        TimelineView(.animation) { [start, inset] context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                Self.drawRings(in: &ctx, size: size, elapsed: elapsed, inset: inset)
            }
        }
        .allowsHitTesting(false)
    }

    private nonisolated static func drawRings(
        in ctx: inout GraphicsContext, size: CGSize, elapsed: TimeInterval, inset: CGFloat
    ) {
        let bounds = CGRect(origin: .zero, size: size)
        for i in 0..<ringCount {
            let t = (elapsed - Double(i) * ringStagger) / ringDuration
            guard t > 0, t < 1 else { continue }
            // Ease in, so the ring accelerates as it's sucked into the card.
            let eased = CGFloat(t * t)
            let rect = bounds.insetBy(dx: inset * eased, dy: inset * eased)
            let shrink = 1 - eased
            let path = Path(roundedRect: rect, cornerRadius: 12 + 48 * shrink, style: .continuous)
            // Quick fade in, then fade out as it lands; trailing rings are a bit fainter.
            let alpha = min(t / 0.2, 1) * (1 - pow(t, 3)) * (1 - 0.25 * Double(i))

            var glow = ctx
            glow.addFilter(.blur(radius: 10 * shrink + 3))
            glow.opacity = alpha * 0.8
            glow.stroke(path, with: .color(.accentColor), lineWidth: 8 * shrink + 3)

            var rim = ctx
            rim.opacity = alpha
            rim.stroke(path, with: .color(.accentColor), lineWidth: 2 * shrink + 1)
        }
    }
}

/// An AppKit button rather than a SwiftUI one: as a real subview it gets its own mouse-down,
/// while clicks anywhere else on the card still reach `DraggableHostingView` and drag the panel.
private struct JoinButton: NSViewRepresentable {
    let help: String
    let action: () -> Void

    final class Button: NSButton {
        var onPress: () -> Void = {}
        // The panel never becomes key, so the first click has to count.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        @objc func press() { onPress() }
    }

    func makeNSView(context: Context) -> Button {
        let button = Button(title: "Join", target: nil, action: #selector(Button.press))
        button.target = button
        button.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .push
        button.controlSize = .large
        button.bezelColor = .controlAccentColor
        return button
    }

    func updateNSView(_ button: Button, context: Context) {
        button.onPress = action
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }
}

/// Hosting view that drags its window on click, since SwiftUI content otherwise swallows the mouse-down
/// and `isMovableByWindowBackground` never kicks in.
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        window?.performDrag(with: event)
    }
}

/// A small always-on-top floating panel showing the meeting title and time remaining.
@MainActor
final class OverlayController: NSObject {
    private static let centerAnimationDuration: CFTimeInterval = 1
    /// How far beyond the card the attention rings start.
    private static let attentionInset: CGFloat = 240

    private let model = OverlayModel()
    private lazy var panel: NSPanel = makePanel()
    private var hasBeenPositioned = false

    /// Where the panel sat before it moved to center, so it can go back there for the next meeting.
    /// Cleared if the user drags it while centered: their new spot wins.
    private var homeOrigin: NSPoint?
    private var isCentered = false

    private var displayLink: CADisplayLink?
    private var animationFrom = NSPoint.zero
    private var animationTo = NSPoint.zero
    private var animationStart: CFTimeInterval = 0

    private var attentionPanel: NSPanel?
    private var attentionDismissal: DispatchWorkItem?

    var isVisible: Bool { panel.isVisible }

    /// Called when the Join button is pressed.
    var onJoin: () -> Void {
        get { model.onJoin }
        set { model.onJoin = newValue }
    }

    /// `centered` moves the panel to the middle of its screen (animated); it stays there until `hide()`.
    /// `joinHelp` names the call (e.g. "Join Google Meet") and shows the Join button; nil hides it.
    func show(title: String, remaining: String, joinHelp: String?, centered: Bool) {
        if model.title != title { model.title = title }
        if model.remaining != remaining { model.remaining = remaining }
        if model.joinHelp != joinHelp { model.joinHelp = joinHelp }
        if !panel.isVisible {
            if !hasBeenPositioned {
                positionTopRight()
                hasBeenPositioned = true
            }
            panel.orderFrontRegardless()
            model.introCount += 1
            playAttention()
        }
        if centered && !isCentered {
            isCentered = true
            homeOrigin = panel.frame.origin
            animate(to: centeredOrigin())
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        stopAnimation()
        dismissAttention()
        if isCentered, let homeOrigin {
            panel.setFrameOrigin(homeOrigin)
        }
        isCentered = false
        homeOrigin = nil
    }

    // MARK: - Attention rings

    private func playAttention() {
        dismissAttention()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let inset = Self.attentionInset
        let frame = panel.frame.insetBy(dx: -inset, dy: -inset)
        let attention = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        attention.contentView = NSHostingView(rootView: AttentionView(start: .now, inset: inset))
        attention.isOpaque = false
        attention.backgroundColor = .clear
        attention.hasShadow = false
        attention.ignoresMouseEvents = true
        attention.level = panel.level
        attention.collectionBehavior = panel.collectionBehavior
        attention.hidesOnDeactivate = false
        attention.isReleasedWhenClosed = false
        attention.setFrame(frame, display: false)
        // As a child window it tracks the card if it's dragged or glides to center mid-effect.
        panel.addChildWindow(attention, ordered: .below)
        attentionPanel = attention

        let dismissal = DispatchWorkItem { [weak self] in self?.dismissAttention() }
        attentionDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + AttentionView.totalDuration + 0.1, execute: dismissal)
    }

    private func dismissAttention() {
        attentionDismissal?.cancel()
        attentionDismissal = nil
        guard let attentionPanel else { return }
        panel.removeChildWindow(attentionPanel)
        attentionPanel.orderOut(nil)
        self.attentionPanel = nil
    }

    // MARK: - Center animation

    private func centeredOrigin() -> NSPoint {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return panel.frame.origin }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
    }

    private func animate(to target: NSPoint) {
        stopAnimation()
        animationFrom = panel.frame.origin
        animationTo = target
        animationStart = CACurrentMediaTime()
        guard let view = panel.contentView else {
            panel.setFrameOrigin(target)
            return
        }
        let link = view.displayLink(target: self, selector: #selector(stepAnimation))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func stepAnimation(_ link: CADisplayLink) {
        let t = (CACurrentMediaTime() - animationStart) / Self.centerAnimationDuration
        let eased = Countdown.easeOutExpo(t)
        panel.setFrameOrigin(NSPoint(
            x: animationFrom.x + (animationTo.x - animationFrom.x) * eased,
            y: animationFrom.y + (animationTo.y - animationFrom.y) * eased
        ))
        if t >= 1 { stopAnimation() }
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func userWillDrag() {
        // Grabbing the panel mid-flight stops the tween; dragging it while centered means "keep it here".
        stopAnimation()
        if isCentered { homeOrigin = nil }
    }

    private func makePanel() -> NSPanel {
        let hosting = DraggableHostingView(rootView: OverlayView(model: model))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        hosting.onMouseDown = { [weak self] in self?.userWillDrag() }
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let margin: CGFloat = 16
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        ))
    }
}
