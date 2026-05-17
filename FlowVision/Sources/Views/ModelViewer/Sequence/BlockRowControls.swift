//
//  BlockRowControls.swift
//  FlowVision
//
//  Shared row controls used by BlockCardView and LoopCardView: the
//  [-] N [+] repeat pill and the trash delete button.
//
//  Infinite-loop semantics (one control, no separate ∞ toggle):
//    - At N=1, pressing [-] enters infinite mode (N=-1).
//    - In infinite mode, [-] is disabled.
//    - In infinite mode, [+] exits back to N=1.
//    - In finite mode at N=99, [+] is disabled.
//

import SwiftUI
import AppKit

struct RepeatPill: View {
    @ObservedObject var node: StepNode
    @ObservedObject var state: SequenceEditorState

    var body: some View {
        HStack(spacing: 0) {
            stepButton(symbol: "minus", enabled: canDecrement) {
                decrement()
            }

            Text(node.repeatCount < 0 ? "∞" : "\(node.repeatCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(minWidth: 26)

            stepButton(symbol: "plus", enabled: canIncrement) {
                increment()
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 28)
        .background(SwiftUI.Color(NSColor.tertiaryLabelColor).opacity(0.18))
        .cornerRadius(14)
    }

    private var canDecrement: Bool { node.repeatCount != -1 }
    private var canIncrement: Bool { node.repeatCount < 99 || node.repeatCount < 0 }

    private func decrement() {
        if node.repeatCount == 1 {
            node.repeatCount = -1   // 1 → ∞
        } else if node.repeatCount > 1 {
            node.repeatCount -= 1
        } else {
            return                  // already ∞ — disabled
        }
        state.markDirty()
    }

    private func increment() {
        if node.repeatCount < 0 {
            node.repeatCount = 1    // ∞ → 1
        } else if node.repeatCount < 99 {
            node.repeatCount += 1
        } else {
            return                  // already 99
        }
        state.markDirty()
    }

    private func stepButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(enabled ? .primary : .secondary.opacity(0.5))
                .frame(width: 24, height: 28)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }
}

struct DeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help("Delete this step")
    }
}
