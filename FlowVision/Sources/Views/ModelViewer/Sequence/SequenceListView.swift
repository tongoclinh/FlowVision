//
//  SequenceListView.swift
//  FlowVision
//
//  Left pane of the editor: list of sequences, +/- buttons, rename.
//

import SwiftUI

struct SequenceListView: View {
    @ObservedObject var state: SequenceEditorState

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { state.selectedEntryId },
                set: {
                    state.selectedEntryId = $0
                    state.selectedNodeId = nil
                }
            )) {
                ForEach(state.entries) { entry in
                    SequenceListRow(state: state, entry: entry)
                        .tag(entry.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 4) {
                Button(action: { state.addSequence() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add sequence")

                Button(action: { state.removeSelectedSequence() }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(state.selectedEntryId == nil)
                .help("Remove selected sequence")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 150, idealWidth: 180, maxWidth: 220)
    }
}

private struct SequenceListRow: View {
    @ObservedObject var state: SequenceEditorState
    @ObservedObject var entry: SequenceEditorEntry
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 4) {
            if renaming {
                TextField("", text: $draftName, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .onExitCommand { renaming = false }
            } else {
                Text(displayName)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        draftName = entry.name
                        renaming = true
                    }
                Spacer()
            }
        }
    }

    private var displayName: String {
        // Show a leading bullet on entries that haven't been saved yet.
        // We can't cheaply check per-entry diffs without an extra snapshot,
        // so we just flag the whole list when the editor is dirty.
        state.isDirty && state.selectedEntryId == entry.id
            ? "• \(entry.name)"
            : entry.name
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            entry.name = trimmed
            state.markDirty()
        }
        renaming = false
    }
}
