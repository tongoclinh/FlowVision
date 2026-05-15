//
//  ModelDetectorProtocol.swift
//  FlowVision
//

import Foundation

protocol ModelDetector {
    static func isModelFolder(at url: URL) -> Bool
}
