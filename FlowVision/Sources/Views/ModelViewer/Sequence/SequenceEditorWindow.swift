//
//  SequenceEditorWindow.swift
//  FlowVision
//
//  NSWindowController hosting the SwiftUI sequence editor. Handles the
//  "save / discard / cancel" prompt when the user closes while there are
//  unsaved changes.
//

import AppKit
import SwiftUI

final class SequenceEditorWindow: NSWindowController, NSWindowDelegate {

    private let state: SequenceEditorState
    /// Local NSEvent monitor for Backspace. Registered while THIS window is
    /// key, deregistered when it resigns or closes — so multi-window setups
    /// don't fire delete on a background editor's selected node.
    private var keyMonitor: Any?

    init(state: SequenceEditorState) {
        self.state = state
        let host = NSHostingController(rootView: SequenceEditorView(state: state))
        let window = NSWindow(contentViewController: host)
        window.title = "Sequence Editor"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 880, height: 540))
        window.minSize = NSSize(width: 720, height: 420)
        window.setFrameAutosaveName("FlowVision.SequenceEditor")
        super.init(window: window)
        window.delegate = self
    }

    deinit {
        removeKeyMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Backspace key monitor

    func windowDidBecomeKey(_ notification: Notification) {
        installKeyMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        removeKeyMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 51 = ANSI Delete / Backspace
            guard event.keyCode == 51 else { return event }
            self?.handleBackspace()
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func handleBackspace() {
        guard state.selectedNodeId != nil else { return }
        // Skip if focus is in a text-edit responder (TextField field editor)
        // so normal text editing isn't interpreted as "delete card".
        let responder = window?.firstResponder
        if responder is NSTextView || responder is NSText { return }
        state.deleteSelected()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard state.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to your sequences?"
        alert.informativeText = "If you close the window, unsaved changes will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:   // Save
            state.save()
            return true
        case .alertSecondButtonReturn:  // Discard
            state.discard()
            return true
        default:                        // Cancel
            return false
        }
    }
}
