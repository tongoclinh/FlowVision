//
//  BlockDragPayload.swift
//  FlowVision
//
//  Pasteboard payload for sequence-editor drag-drop.
//
//  Pasteboard type: we carry our JSON via `public.data` rather than a
//  custom UTI because:
//    - SwiftUI's `.onDrop(of:isTargeted:perform:)` on macOS 11 silently
//      ignores type identifiers that aren't registered as UTIs anywhere
//      in the system. Registering a custom UTI in Info.plist works, but
//      adds project chrome we don't need.
//    - `public.data` is universal and always recognized.
//    - We strictly validate that any decoded data matches our schema, so
//      we won't accidentally accept arbitrary files / generic drags.
//

import Foundation
import AppKit

enum BlockKind: String, Codable {
    case animation
    case loop
}

enum BlockDragPayload: Codable, Equatable {
    /// Spawn a fresh animation step. `name` is the specific animation chosen
    /// from the palette; empty for an unspecified default.
    case paletteAnimation(name: String)
    /// Spawn a fresh empty loop container.
    case paletteLoop
    /// Move an existing node already in the editor's tree.
    case existing(nodeId: UUID)

    /// "public.data" — a universally recognized UTI that doesn't need
    /// Info.plist registration to participate in SwiftUI drag-drop.
    static let pasteboardType = "public.data"

    func itemProvider() -> NSItemProvider {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.pasteboardType,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// Resolve a payload from an `.onDrop` provider list. Completion fires
    /// on the main queue. Returns nil if no provider matches OR if the
    /// data doesn't decode to one of our schema cases — important because
    /// `public.data` accepts unrelated drags.
    static func decode(
        from providers: [NSItemProvider],
        completion: @escaping (BlockDragPayload?) -> Void
    ) {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(pasteboardType)
        }) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: pasteboardType) { data, _ in
            let payload: BlockDragPayload?
            if let data = data {
                payload = try? JSONDecoder().decode(BlockDragPayload.self, from: data)
            } else {
                payload = nil
            }
            DispatchQueue.main.async { completion(payload) }
        }
    }
}
