//
//  SequenceModel.swift
//  FlowVision
//
//  Persisted data model for nested-loop animation sequences. Lives in
//  `.flowvision.json` next to the model. Pure value types, no AppKit.
//

import Foundation

/// One step in a nested animation sequence. Either plays an animation N times,
/// or runs a nested group of steps N times. `repeatCount == -1` means infinite.
indirect enum SequenceStep: Equatable {
    case animation(name: String, repeatCount: Int, mixDuration: Float)
    case group(steps: [SequenceStep], repeatCount: Int)
}

extension SequenceStep: Codable {
    private enum Kind: String, Codable {
        case animation, group
    }

    private enum CodingKeys: String, CodingKey {
        case kind, name, repeatCount, mixDuration, steps
    }

    static let defaultMixDuration: Float = 0.2

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        switch kind {
        case .animation:
            let name = try c.decode(String.self, forKey: .name)
            let mix = try c.decodeIfPresent(Float.self, forKey: .mixDuration) ?? Self.defaultMixDuration
            self = .animation(name: name, repeatCount: repeatCount, mixDuration: mix)
        case .group:
            let steps = try c.decodeIfPresent([SequenceStep].self, forKey: .steps) ?? []
            self = .group(steps: steps, repeatCount: repeatCount)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .animation(name, repeatCount, mixDuration):
            try c.encode(Kind.animation, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(repeatCount, forKey: .repeatCount)
            try c.encode(mixDuration, forKey: .mixDuration)
        case let .group(steps, repeatCount):
            try c.encode(Kind.group, forKey: .kind)
            try c.encode(repeatCount, forKey: .repeatCount)
            try c.encode(steps, forKey: .steps)
        }
    }
}

/// Top-level named sequence persisted in the sidecar. Always has a root group;
/// a single animation is encoded as a group-of-one for uniform tree handling.
struct AnimSequence: Codable, Equatable {
    var name: String
    var root: SequenceStep

    init(name: String, root: SequenceStep) {
        self.name = name
        self.root = root
    }
}

#if DEBUG
enum SequenceModelSelfTest {
    /// Sanity round-trip check used during development. Not a real unit test.
    /// Call from a debugger if the Codable schema is ever modified.
    static func roundTrip() -> Bool {
        let sample = AnimSequence(
            name: "Combo 1",
            root: .group(steps: [
                .animation(name: "A", repeatCount: 1, mixDuration: 0.2),
                .group(steps: [
                    .animation(name: "B", repeatCount: 1, mixDuration: 0.15),
                    .animation(name: "C", repeatCount: 2, mixDuration: 0.15),
                ], repeatCount: 4),
                .animation(name: "D", repeatCount: 1, mixDuration: 0.2),
            ], repeatCount: 1)
        )
        do {
            let data = try JSONEncoder().encode(sample)
            let decoded = try JSONDecoder().decode(AnimSequence.self, from: data)
            return decoded == sample
        } catch {
            return false
        }
    }
}
#endif
