//
//  SpineControlsBar.swift
//  FlowVision
//

import AppKit

class SpineControlsBar: NSVisualEffectView {
    var onPlayPause: (() -> Void)?
    var onSelectAnimation: ((String) -> Void)?
    var onSelectSkin: ((String) -> Void)?
    var onChangeSpeed: ((Float) -> Void)?
    var onToggleLoop: ((Bool) -> Void)?
    var onChangeBgColor: ((NSColor) -> Void)?

    private let animScroll = NSScrollView()
    private let animStack = NSStackView()
    private let playBtn = NSButton()
    private let loopBtn = NSButton()
    private let speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let skinPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let skinLabel = NSTextField(labelWithString: "Skin:")
    private let timeLabel = NSTextField(labelWithString: "")
    private let bgColorWell = NSColorWell()
    private var animButtons: [NSButton] = []
    private var isLooping = true

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

        skinLabel.font = .systemFont(ofSize: 11)
        skinLabel.textColor = .secondaryLabelColor
        configPopup(skinPopup, action: #selector(skinChanged))

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        bgColorWell.color = .black
        bgColorWell.target = self
        bgColorWell.action = #selector(bgColorChanged)
        if #available(macOS 13.0, *) { bgColorWell.colorWellStyle = .minimal }

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let controls = NSStackView(views: [
            playBtn, loopBtn, speedPopup,
            makeVerticalSeparator(), skinLabel, skinPopup,
            spacer, timeLabel, bgColorWell
        ])
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.alignment = .centerY
        controls.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        controls.translatesAutoresizingMaskIntoConstraints = false

        addSubview(animScroll)
        addSubview(sep)
        addSubview(controls)

        NSLayoutConstraint.activate([
            animScroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            animScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            animScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            animScroll.heightAnchor.constraint(equalToConstant: 24),
            sep.topAnchor.constraint(equalTo: animScroll.bottomAnchor, constant: 4),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            controls.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
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

    private func makeVerticalSeparator() -> NSView {
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

    func setSkins(_ names: [String]) {
        skinPopup.removeAllItems()
        names.forEach { skinPopup.addItem(withTitle: $0) }
        let hide = names.count <= 1
        skinPopup.isHidden = hide
        skinLabel.isHidden = hide
    }

    func updatePlayState(_ playing: Bool) {
        playBtn.image = NSImage(
            systemSymbolName: playing ? "pause.fill" : "play.fill",
            accessibilityDescription: nil
        )
    }

    func updateTime(current: Float, duration: Float) {
        timeLabel.stringValue = String(format: "%.1f / %.1fs", current, duration)
    }

    // MARK: - Actions

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

    @objc private func skinChanged() {
        guard let name = skinPopup.titleOfSelectedItem else { return }
        onSelectSkin?(name)
    }

    @objc private func speedChanged() {
        let title = speedPopup.titleOfSelectedItem ?? "1×"
        let value = Float(title.replacingOccurrences(of: "×", with: "")) ?? 1.0
        onChangeSpeed?(value)
    }

    @objc private func bgColorChanged() { onChangeBgColor?(bgColorWell.color) }
}

private class DynamicSeparatorView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() { layer?.backgroundColor = NSColor.separatorColor.cgColor }
}
