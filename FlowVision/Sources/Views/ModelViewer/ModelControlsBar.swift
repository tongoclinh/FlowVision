//
//  ModelControlsBar.swift
//  FlowVision
//

import AppKit

class ModelControlsBar: NSVisualEffectView {
    var onPlayPause: (() -> Void)?
    var onSelectAnimation: ((String) -> Void)?
    var onChangeSpeed: ((Float) -> Void)?
    var onToggleLoop: ((Bool) -> Void)?
    var onChangeBgColor: ((NSColor) -> Void)?
    var onChangeBgMode: ((BackgroundMode) -> Void)?
    var onScrub: ((Float) -> Void)?
    var onScrubEnd: (() -> Void)?
    /// User clicked a sequence button. Viewer controller decides whether to
    /// start or toggle off based on whether this sequence is already playing.
    var onRunSequence: ((AnimSequence) -> Void)?
    /// User clicked the "Edit Sequences…" button.
    var onOpenSequenceEditor: (() -> Void)?

    var additionalControlsView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let v = additionalControlsView {
                v.translatesAutoresizingMaskIntoConstraints = false
                controlsStack.insertArrangedSubview(v, at: additionalControlsInsertIndex)
            }
        }
    }

    private let animScroll = NSScrollView()
    private let animStack = NSStackView()
    private let playBtn = NSButton()
    private let loopBtn = NSButton()
    private let speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let timeSlider = ScrubSlider()
    private let timeLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private(set) var isScrubbing = false
    private let bgColorWell = NSColorWell()
    private let bgModeSegment = NSSegmentedControl()
    private var animButtons: [NSButton] = []
    private var isLooping = true
    private var controlsStack: NSStackView!
    private let additionalControlsInsertIndex = 3

    // Sequence row (Phase 7). Hidden by default; revealed when a model viewer
    // calls setSequences(_:) — even if the array is empty, the row stays
    // visible because the "Edit Sequences…" entry-point lives there.
    private let sequenceScroll = NSScrollView()
    private let sequenceStack = NSStackView()
    private let editSequencesBtn = NSButton()
    private var sequenceButtons: [NSButton] = []
    private var sequences: [AnimSequence] = []
    private var playingSequenceName: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .withinWindow
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupUI() {
        animStack.orientation = .horizontal
        animStack.spacing = 4
        animScroll.documentView = animStack
        animScroll.hasHorizontalScroller = false
        animScroll.hasVerticalScroller = false
        animScroll.drawsBackground = false
        animScroll.translatesAutoresizingMaskIntoConstraints = false

        configSymbolButton(playBtn, symbol: "pause.fill", action: #selector(playPauseTapped))
        configSymbolButton(loopBtn, symbol: "repeat", action: #selector(loopTapped))
        loopBtn.contentTintColor = .controlAccentColor

        ["0.25×", "0.5×", "1×", "1.5×", "2×", "3×"].forEach { speedPopup.addItem(withTitle: $0) }
        speedPopup.selectItem(withTitle: "1×")
        configPopup(speedPopup, action: #selector(speedChanged))

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        timeSlider.minValue = 0
        timeSlider.maxValue = 1
        timeSlider.doubleValue = 0
        timeSlider.isContinuous = true
        timeSlider.controlSize = .small
        timeSlider.target = self
        timeSlider.action = #selector(sliderChanged)
        timeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        timeSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // NSSlider with isContinuous=true does not deliver its action on mouseUp,
        // so rely on the subclass's explicit mouseUp hook to clear scrubbing state.
        timeSlider.onTrackingEnd = { [weak self] in
            guard let self else { return }
            self.isScrubbing = false
            self.onScrubEnd?()
        }

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.setContentHuggingPriority(.required, for: .horizontal)
        zoomLabel.alignment = .right

        bgModeSegment.segmentCount = 3
        bgModeSegment.setLabel("Solid", forSegment: 0)
        bgModeSegment.setLabel("◻ Dark", forSegment: 1)
        bgModeSegment.setLabel("◻ Light", forSegment: 2)
        bgModeSegment.selectedSegment = 0
        bgModeSegment.controlSize = .small
        bgModeSegment.font = .systemFont(ofSize: 10)
        bgModeSegment.target = self
        bgModeSegment.action = #selector(bgModeChanged)
        bgModeSegment.setContentHuggingPriority(.required, for: .horizontal)

        bgColorWell.color = .black
        bgColorWell.target = self
        bgColorWell.action = #selector(bgColorChanged)
        if #available(macOS 13.0, *) { bgColorWell.colorWellStyle = .minimal }

        sequenceStack.orientation = .horizontal
        sequenceStack.spacing = 4
        sequenceScroll.documentView = sequenceStack
        sequenceScroll.hasHorizontalScroller = false
        sequenceScroll.hasVerticalScroller = false
        sequenceScroll.drawsBackground = false
        sequenceScroll.translatesAutoresizingMaskIntoConstraints = false
        sequenceScroll.isHidden = true

        editSequencesBtn.title = "Edit Sequences…"
        editSequencesBtn.bezelStyle = .recessed
        editSequencesBtn.controlSize = .small
        editSequencesBtn.font = .systemFont(ofSize: 11)
        editSequencesBtn.target = self
        editSequencesBtn.action = #selector(editSequencesTapped)
        editSequencesBtn.translatesAutoresizingMaskIntoConstraints = false
        editSequencesBtn.isHidden = true

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        // Single flex item (timeSlider) — having two `defaultLow`-hugging items
        // in an NSStackView with .gravityAreas distribution caused the slider
        // to be intermittently squeezed to 0 width while a sibling spacer
        // claimed all the free space. Letting the slider stretch and packing
        // the trailing items right after the time label is both simpler and
        // deterministic.
        controlsStack = NSStackView(views: [
            playBtn, loopBtn, speedPopup,
            timeSlider, timeLabel, zoomLabel, bgModeSegment, bgColorWell
        ])
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 6
        controlsStack.alignment = .centerY
        controlsStack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(animScroll)
        addSubview(sequenceScroll)
        addSubview(editSequencesBtn)
        addSubview(sep)
        addSubview(controlsStack)

        NSLayoutConstraint.activate([
            animScroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            animScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            animScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            animScroll.heightAnchor.constraint(equalToConstant: 24),
            sequenceScroll.topAnchor.constraint(equalTo: animScroll.bottomAnchor, constant: 4),
            sequenceScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sequenceScroll.trailingAnchor.constraint(equalTo: editSequencesBtn.leadingAnchor, constant: -8),
            sequenceScroll.heightAnchor.constraint(equalToConstant: 24),
            editSequencesBtn.centerYAnchor.constraint(equalTo: sequenceScroll.centerYAnchor),
            editSequencesBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sep.topAnchor.constraint(equalTo: sequenceScroll.bottomAnchor, constant: 4),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            controlsStack.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            controlsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    private func configSymbolButton(_ btn: NSButton, symbol: String, action: Selector) {
        btn.bezelStyle = .accessoryBarAction
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        btn.isBordered = false
        btn.target = self
        btn.action = action
    }

    private func configPopup(_ popup: NSPopUpButton, action: Selector) {
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.target = self
        popup.action = action
    }

    func makeVerticalSeparator() -> NSView {
        let v = DynamicSeparatorView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return v
    }

    // MARK: - Public

    func setAnimations(_ names: [String], selected: String?) {
        animButtons.forEach { $0.removeFromSuperview() }
        animButtons.removeAll()
        for name in names {
            let btn = NSButton(title: name, target: self, action: #selector(animTapped(_:)))
            btn.bezelStyle = .recessed
            btn.setButtonType(.pushOnPushOff)
            btn.controlSize = .small
            btn.font = .systemFont(ofSize: 11)
            btn.state = (name == selected) ? .on : .off
            animStack.addArrangedSubview(btn)
            animButtons.append(btn)
        }
        animStack.layoutSubtreeIfNeeded()
        let size = animStack.fittingSize
        let scrollHeight = max(animScroll.contentView.bounds.height, 24)
        animStack.frame = NSRect(x: 0, y: 0,
            width: max(size.width, animScroll.contentView.bounds.width),
            height: scrollHeight)
    }

    func updatePlayState(_ playing: Bool) {
        playBtn.image = NSImage(
            systemSymbolName: playing ? "pause.fill" : "play.fill",
            accessibilityDescription: nil
        )
    }

    func updateTime(current: Float, duration: Float) {
        timeLabel.stringValue = String(format: "%.1f / %.1fs", current, duration)
        if !isScrubbing && duration > 0 {
            timeSlider.maxValue = Double(duration)
            timeSlider.doubleValue = Double(current)
        }
    }

    var currentBgMode: BackgroundMode {
        switch bgModeSegment.selectedSegment {
        case 1: return .checker(.dark)
        case 2: return .checker(.light)
        default: return .solid(bgColorWell.color)
        }
    }

    var selectedAnimationName: String? {
        animButtons.first(where: { $0.state == .on })?.title
    }

    var currentSpeed: Float {
        let title = speedPopup.titleOfSelectedItem ?? "1×"
        return Float(title.replacingOccurrences(of: "×", with: "")) ?? 1.0
    }

    var currentLoopState: Bool { isLooping }

    func selectAnimationByName(_ name: String) {
        guard let btn = animButtons.first(where: { $0.title == name }) else { return }
        selectAnimation(btn)
    }

    func setSpeed(_ speed: Float) {
        let label = "\(speed == Float(Int(speed)) ? String(format: "%.0f", speed) : String(format: "%g", speed))×"
        if speedPopup.itemTitles.contains(label) {
            speedPopup.selectItem(withTitle: label)
        }
    }

    func setLoopState(_ loop: Bool) {
        isLooping = loop
        loopBtn.contentTintColor = isLooping ? .controlAccentColor : .secondaryLabelColor
    }

    func applyBgMode(_ mode: BackgroundMode) {
        switch mode {
        case .solid(let color):
            bgModeSegment.selectedSegment = 0
            bgColorWell.isHidden = false
            bgColorWell.color = color
        case .checker(let variant):
            bgModeSegment.selectedSegment = variant == .dark ? 1 : 2
            bgColorWell.isHidden = true
        }
    }

    func updateZoom(_ scale: CGFloat) {
        let pct = scale * 100
        if pct < 10 {
            zoomLabel.stringValue = String(format: "%.1f%%", pct)
        } else {
            zoomLabel.stringValue = String(format: "%.0f%%", pct)
        }
    }

    // MARK: - Sequences (Phase 7)

    /// Replace the sequence button row. Pass `[]` to keep the "Edit Sequences…"
    /// entry-point visible with no per-sequence buttons.
    func setSequences(_ sequences: [AnimSequence]) {
        self.sequences = sequences
        sequenceButtons.forEach { $0.removeFromSuperview() }
        sequenceButtons.removeAll()
        for seq in sequences {
            let btn = NSButton(title: seq.name, target: self, action: #selector(sequenceTapped(_:)))
            btn.bezelStyle = .recessed
            btn.setButtonType(.pushOnPushOff)
            btn.controlSize = .small
            btn.font = .systemFont(ofSize: 11)
            btn.state = (seq.name == playingSequenceName) ? .on : .off
            sequenceStack.addArrangedSubview(btn)
            sequenceButtons.append(btn)
        }
        sequenceStack.layoutSubtreeIfNeeded()
        let size = sequenceStack.fittingSize
        let scrollHeight = max(sequenceScroll.contentView.bounds.height, 24)
        sequenceStack.frame = NSRect(x: 0, y: 0,
            width: max(size.width, sequenceScroll.contentView.bounds.width),
            height: scrollHeight)
        // Always show the row once a viewer has wired it — even an empty list
        // needs the "Edit Sequences…" entry-point.
        sequenceScroll.isHidden = false
        editSequencesBtn.isHidden = false
    }

    /// Highlight the sequence button whose name matches `name`. Pass `nil`
    /// to clear all highlights. Visual only — never invokes button actions.
    func setSequencePlaying(_ name: String?) {
        playingSequenceName = name
        for btn in sequenceButtons {
            btn.state = (btn.title == name) ? .on : .off
        }
    }

    /// Set the animation row's visual highlight without firing the
    /// `onSelectAnimation` callback. Used by SequenceRunner to mirror the
    /// currently-playing leaf in the existing animation row.
    func setHighlight(animationName name: String?) {
        for btn in animButtons {
            btn.state = (btn.title == name) ? .on : .off
        }
    }

    @objc private func sequenceTapped(_ sender: NSButton) {
        guard let seq = sequences.first(where: { $0.name == sender.title }) else { return }
        onRunSequence?(seq)
    }

    @objc private func editSequencesTapped() { onOpenSequenceEditor?() }

    // MARK: - Actions

    @objc private func sliderChanged() {
        // Only flag a mouse-drag scrub. Arrow-key adjustments leave the mouse
        // unpressed and produce no mouseUp, so they would otherwise pin
        // isScrubbing=true and freeze the auto-updating thumb.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            isScrubbing = true
        }
        onScrub?(Float(timeSlider.doubleValue))
    }

    @objc private func playPauseTapped() { onPlayPause?() }

    @objc private func loopTapped() {
        isLooping.toggle()
        loopBtn.contentTintColor = isLooping ? .controlAccentColor : .secondaryLabelColor
        onToggleLoop?(isLooping)
    }

    @objc private func animTapped(_ sender: NSButton) { selectAnimation(sender) }

    private func selectAnimation(_ button: NSButton) {
        animButtons.forEach { $0.state = ($0 == button) ? .on : .off }
        onSelectAnimation?(button.title)
    }

    func selectAdjacentAnimation(next: Bool) {
        guard let idx = animButtons.firstIndex(where: { $0.state == .on }) else { return }
        let newIdx = next ? idx + 1 : idx - 1
        guard animButtons.indices.contains(newIdx) else { return }
        selectAnimation(animButtons[newIdx])
    }

    @objc private func speedChanged() {
        let title = speedPopup.titleOfSelectedItem ?? "1×"
        let value = Float(title.replacingOccurrences(of: "×", with: "")) ?? 1.0
        onChangeSpeed?(value)
    }

    @objc private func bgColorChanged() {
        onChangeBgColor?(bgColorWell.color)
        onChangeBgMode?(.solid(bgColorWell.color))
    }

    @objc private func bgModeChanged() {
        let seg = bgModeSegment.selectedSegment
        bgColorWell.isHidden = seg != 0
        switch seg {
        case 1: onChangeBgMode?(.checker(.dark))
        case 2: onChangeBgMode?(.checker(.light))
        default: onChangeBgMode?(.solid(bgColorWell.color))
        }
    }
}

/// NSSlider with isContinuous=true never invokes its action on mouseUp,
/// leaving callers unable to detect end-of-scrub. This override fills that gap.
private class ScrubSlider: NSSlider {
    var onTrackingEnd: (() -> Void)?
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onTrackingEnd?()
    }
}

class DynamicSeparatorView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() { layer?.backgroundColor = NSColor.separatorColor.cgColor }
}
