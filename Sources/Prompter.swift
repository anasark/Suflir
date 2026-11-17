import AppKit

/// A window that never takes focus and may sit over the menu bar.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class PrompterTextView: NSTextView {
    var onClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The black strip hanging from the notch, and the scrolling text inside it.
final class PrompterController {
    private let state = AppState.shared

    let panel: NotchPanel
    private let background = NSView()
    private let scrollView = NSScrollView()
    private let textView = PrompterTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    private let dot = NSView()

    /// Called when the user clicks the strip.
    var onClick: (() -> Void)?
    /// Called when auto-scroll reaches the end of the script.
    var onReachedEnd: (() -> Void)?

    // Script broken into words, for voice following.
    private var wordRanges: [NSRange] = []
    private var words: [String] = []
    /// Index of the next word the speaker is expected to say.
    private var position = 0
    private var lastTranscript = ""

    private var scrollY: CGFloat = 0
    private var targetY: CGFloat = 0
    private var contentHeight: CGFloat = 0
    private var movingProgrammatically = false
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()

    private let readColor = NSColor(white: 1, alpha: 0.35)
    private let unreadColor = NSColor.white
    private static let wordPattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}'’]+")

    init() {
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered,
                           defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.cgColor
        background.layer?.cornerRadius = 18
        background.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        background.layer?.masksToBounds = true
        panel.contentView = background

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none
        background.addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 14, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.onClick = { [weak self] in self?.onClick?() }
        scrollView.documentView = textView

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        background.addSubview(dot)

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(clipMoved),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        applySharing()
        applyBackground()
        layoutPanel()
        reloadText()
        setPlaying(false)
    }

    // MARK: Layout

    /// The screen with the notch if there is one, otherwise the main screen.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    @objc private func screensChanged() { layoutPanel() }

    func layoutPanel() {
        guard let screen = targetScreen else { return }
        let notch = screen.safeAreaInsets.top
        let width = CGFloat(state.width)
        let textHeight = CGFloat(state.textHeight)

        // With a notch, the strip starts at the very top and the text begins
        // just under the notch. Without one, it hangs below the menu bar.
        let top = notch > 0 ? screen.frame.maxY : screen.visibleFrame.maxY
        let height = notch + textHeight
        let frame = NSRect(x: (screen.frame.midX - width / 2).rounded(),
                           y: top - height,
                           width: width,
                           height: height)
        panel.setFrame(frame, display: true)
        scrollView.frame = NSRect(x: 0, y: 8, width: width, height: textHeight - 8)
        dot.frame = NSRect(x: width - 14, y: 8, width: 6, height: 6)
        relayoutText()
    }

    func applySharing() {
        panel.sharingType = state.hideFromShare ? .none : .readOnly
    }

    func applyBackground() {
        let alpha = CGFloat(min(max(state.backgroundOpacity, 0), 1))
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
        styleText()
    }

    func show() {
        layoutPanel()
        panel.orderFrontRegardless()
        startTimer()
    }

    func hide() {
        panel.orderOut(nil)
        timer?.invalidate()
        timer = nil
    }

    func setPlaying(_ playing: Bool) {
        dot.layer?.backgroundColor = (playing ? NSColor.systemGreen : NSColor(white: 1, alpha: 0.25)).cgColor
    }

    // MARK: Text

    func reloadText() {
        let script = state.script
        let ns = script as NSString
        wordRanges = Self.wordPattern.matches(in: script, range: NSRange(location: 0, length: ns.length)).map(\.range)
        words = wordRanges.map { Self.normalize(ns.substring(with: $0)) }
        textView.string = script
        relayoutText()
        // Keep the reading place if the script still reaches that far.
        position = min(position, words.count)
        lastTranscript = ""
        styleText()
    }

    private func relayoutText() {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let clip = scrollView.contentSize
        textView.font = NSFont.systemFont(ofSize: CGFloat(state.fontSize), weight: .medium)
        styleText()
        textView.setFrameSize(NSSize(width: clip.width, height: max(textView.frame.height, clip.height)))
        layout.ensureLayout(for: container)
        contentHeight = layout.usedRect(for: container).height
        // Extra room at the bottom lets the last line travel up to the top.
        textView.setFrameSize(NSSize(width: clip.width, height: contentHeight + clip.height))
        scrollY = min(scrollY, maxScroll)
        targetY = min(targetY, maxScroll)
        moveClip(to: scrollY)
    }

    private var maxScroll: CGFloat {
        max(0, contentHeight - CGFloat(state.fontSize))
    }

    /// Dims the words already spoken (voice mode only).
    private func styleText() {
        guard let storage = textView.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(state.fontSize) * 0.2
        paragraph.alignment = .center
        storage.beginEditing()
        storage.addAttribute(.paragraphStyle, value: paragraph, range: all)
        storage.addAttribute(.foregroundColor, value: unreadColor, range: all)
        if state.backgroundOpacity < 0.85 {
            // A dark outline keeps white text readable over bright windows.
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.95)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = .zero
            storage.addAttribute(.shadow, value: shadow, range: all)
        } else {
            storage.removeAttribute(.shadow, range: all)
        }
        if state.mode == .voice, position > 0, position <= wordRanges.count {
            let end = NSMaxRange(wordRanges[position - 1])
            storage.addAttribute(.foregroundColor, value: readColor, range: NSRange(location: 0, length: end))
        }
        storage.endEditing()
    }

    func modeChanged() {
        if state.mode == .voice {
            position = wordIndex(atY: scrollY)
            targetY = scrollY
        }
        lastTranscript = ""
        styleText()
    }

    // MARK: Scrolling

    private func startTimer() {
        timer?.invalidate()
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now

        var next = scrollY
        if state.mode == .auto {
            guard state.isPlaying else { return }
            next = min(scrollY + CGFloat(state.speed * dt), maxScroll)
            if next >= maxScroll { onReachedEnd?() }
        } else {
            // Voice mode: glide toward the line being spoken.
            next = scrollY + (targetY - scrollY) * CGFloat(min(1, dt * 6))
            if abs(targetY - next) < 0.25 { next = targetY }
        }
        if next != scrollY {
            scrollY = next
            moveClip(to: next)
        }
    }

    private func moveClip(to y: CGFloat) {
        movingProgrammatically = true
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        movingProgrammatically = false
    }

    /// The user scrolled with the trackpad or mouse wheel.
    @objc private func clipMoved() {
        guard !movingProgrammatically else { return }
        let y = min(max(0, scrollView.contentView.bounds.origin.y), maxScroll)
        scrollY = y
        targetY = y
        if state.mode == .voice {
            position = wordIndex(atY: y)
            lastTranscript = ""
            styleText()
        }
    }

    func scroll(lines: CGFloat) {
        let lineHeight = CGFloat(state.fontSize) * 1.4
        jump(to: (state.mode == .voice ? targetY : scrollY) + lines * lineHeight)
    }

    func restart() {
        position = 0
        jump(to: 0)
    }

    private func jump(to y: CGFloat) {
        let clamped = min(max(0, y), maxScroll)
        targetY = clamped
        if state.mode == .voice {
            position = wordIndex(atY: clamped)
            lastTranscript = ""
            styleText()
        } else {
            scrollY = clamped
            moveClip(to: clamped)
        }
    }

    // MARK: Voice following

    private static func normalize(_ word: String) -> String {
        word.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
    }

    private static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Forgive small endings: "walk" vs "walked", "kata" vs "katanya".
        guard a.count >= 4, b.count >= 4 else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    /// Takes everything heard so far and moves the reading place forward
    /// to where the last few spoken words appear in the script.
    func heard(_ transcript: String) {
        guard state.mode == .voice, transcript != lastTranscript, !words.isEmpty else { return }
        lastTranscript = transcript

        let ns = transcript as NSString
        let spoken = Self.wordPattern
            .matches(in: transcript, range: NSRange(location: 0, length: ns.length))
            .suffix(4)
            .map { Self.normalize(ns.substring(with: $0.range)) }
        guard let last = spoken.last, position < words.count else { return }

        var best: (index: Int, score: Int)?
        let limit = min(words.count, position + 40)
        for j in position..<limit where Self.sameWord(words[j], last) {
            // Count how many spoken words line up, walking backwards.
            var score = 1
            var k = 1
            while k < spoken.count, j - k >= 0,
                  Self.sameWord(words[j - k], spoken[spoken.count - 1 - k]) {
                score += 1
                k += 1
            }
            // The further the jump, the more words must agree.
            let distance = j - position
            let needed = distance <= 1 ? 1 : (distance <= 8 ? 2 : 3)
            guard score >= needed else { continue }
            if best == nil || score > best!.score { best = (j, score) }
        }
        guard let best else { return }
        setPosition(best.index + 1)
    }

    private func setPosition(_ newPosition: Int) {
        let old = position
        position = min(max(0, newPosition), words.count)
        guard position != old, let storage = textView.textStorage else { return }
        if position > old {
            let start = wordRanges[old].location
            let end = NSMaxRange(wordRanges[position - 1])
            storage.addAttribute(.foregroundColor, value: readColor, range: NSRange(location: start, length: end - start))
        } else {
            styleText()
        }
        targetY = min(lineTop(ofWord: min(position, words.count - 1)), maxScroll)
    }

    /// Scroll offset that puts the given word's line at the top of the strip.
    private func lineTop(ofWord index: Int) -> CGFloat {
        guard let layout = textView.layoutManager, wordRanges.indices.contains(index) else { return 0 }
        let glyphs = layout.glyphRange(forCharacterRange: wordRanges[index], actualCharacterRange: nil)
        let rect = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        return max(0, rect.minY)
    }

    /// First word on the line shown at the top for a given scroll offset.
    private func wordIndex(atY y: CGFloat) -> Int {
        guard let layout = textView.layoutManager, let container = textView.textContainer,
              !wordRanges.isEmpty, y > 1 else { return 0 }
        let point = NSPoint(x: 1, y: y + CGFloat(state.fontSize) * 0.6)
        let glyph = layout.glyphIndex(for: point, in: container)
        let lineGlyphs = layoutLineRange(layout, glyph)
        let char = layout.characterIndexForGlyph(at: lineGlyphs.location)
        // Binary search for the first word starting at or after that character.
        var low = 0
        var high = wordRanges.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(wordRanges[mid]) <= char { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func layoutLineRange(_ layout: NSLayoutManager, _ glyph: Int) -> NSRange {
        var range = NSRange(location: glyph, length: 0)
        guard glyph < layout.numberOfGlyphs else { return range }
        _ = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
        return range
    }
}
