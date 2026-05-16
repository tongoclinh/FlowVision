//
//  ModelViewerProtocol.swift
//  FlowVision
//

import AppKit
import MetalKit

protocol ModelViewer: AnyObject {
    var viewerView: MTKView { get }
    var isYAxisFlipped: Bool { get }
    func setProjection(visibleBounds: CGRect)
    func originalBounds() -> CGRect
    func applyBackground(_ mode: BackgroundMode)
    func captureSnapshot(maxSize: CGFloat) -> CGImage?
}

extension ModelViewer {
    func applyBackground(_ mode: BackgroundMode) {
        switch mode {
        case .solid(let color):
            let c = color.usingColorSpace(.sRGB) ?? color
            viewerView.clearColor = MTLClearColor(
                red: Double(c.redComponent), green: Double(c.greenComponent),
                blue: Double(c.blueComponent), alpha: 1.0)
            viewerView.layer?.isOpaque = true
        case .checker:
            viewerView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            viewerView.layer?.isOpaque = false
        }
    }

    func captureSnapshot(maxSize: CGFloat) -> CGImage? { nil }
}

/// Texture-to-CGImage capture utility shared across model viewers.
///
/// Requires the source texture to have been created with `framebufferOnly = false`
/// on its MTKView, otherwise `getBytes` will fail silently.
enum ModelSnapshot {
    static func cgImage(from texture: MTLTexture, maxSize: CGFloat) -> CGImage? {
        let width = texture.width
        let height = texture.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        var bytes = [UInt8](repeating: 0, count: totalBytes)

        texture.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        // Metal's BGRA8Unorm matches CGImage with .byteOrder32Little + premultipliedFirst.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            .byteOrder32Little,
        ]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        guard let full = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: bitmapInfo, provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return resize(full, maxSize: maxSize)
    }

    private static func resize(_ image: CGImage, maxSize: CGFloat) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let longest = max(w, h)
        if longest <= maxSize { return image }

        let scale = maxSize / longest
        let newW = Int(w * scale)
        let newH = Int(h * scale)
        guard newW > 0, newH > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage()
    }
}
