import AppKit
import Foundation

struct AppIconRenderer {
    let sourceURL: URL
    let outputDirectoryURL: URL
    var shouldRenderFullSourceImage: Bool {
        sourceURL.pathExtension.lowercased() != "svg"
    }

    func render() throws {
        guard let glyphImage = NSImage(contentsOf: sourceURL) else {
            throw NSError(domain: "MicLockIcon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to load source SVG at \(sourceURL.path)"
            ])
        }

        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        let outputs: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for (filename, pixelSize) in outputs {
            let bitmap = try renderIcon(sourceImage: glyphImage, pixelSize: pixelSize)
            try writePNG(bitmap: bitmap, to: outputDirectoryURL.appendingPathComponent(filename))
        }
    }

    private func renderIcon(sourceImage: NSImage, pixelSize: Int) throws -> NSBitmapImageRep {
        let size = NSSize(width: pixelSize, height: pixelSize)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: pixelSize,
                                            pixelsHigh: pixelSize,
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "MicLockIcon", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create bitmap context for \(pixelSize)x\(pixelSize)"
            ])
        }

        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        graphicsContext.imageInterpolation = .high

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        if shouldRenderFullSourceImage {
            drawFullSourceImage(sourceImage, in: NSRect(origin: .zero, size: size), pixelSize: pixelSize)
            return bitmap
        }

        let bounds = NSRect(origin: .zero, size: size)
        let radius = CGFloat(pixelSize) * 0.2237
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

        backgroundPath.addClip()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.23, alpha: 1.0),
            NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.10, alpha: 1.0)
        ])
        gradient?.draw(in: bounds, angle: -35.0)

        let glowColor = NSColor(calibratedRed: 0.20, green: 0.88, blue: 0.80, alpha: 0.22)
        glowColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: CGFloat(pixelSize) * 0.12,
                                    y: CGFloat(pixelSize) * 0.58,
                                    width: CGFloat(pixelSize) * 0.52,
                                    height: CGFloat(pixelSize) * 0.36)).fill()

        let glyphInset = CGFloat(pixelSize) * 0.205
        let glyphRect = bounds.insetBy(dx: glyphInset, dy: glyphInset)
        drawTemplateImage(sourceImage, in: glyphRect, color: NSColor.white.withAlphaComponent(0.96))

        return bitmap
    }

    private func drawFullSourceImage(_ image: NSImage, in bounds: NSRect, pixelSize: Int) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        NSGraphicsContext.current?.imageInterpolation = .high

        context.saveGState()
        let radius = CGFloat(pixelSize) * 0.2237
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()

        let sourceSize = image.size
        let sourceLength = min(sourceSize.width, sourceSize.height)
        let cropInset = sourceLength * 0.075
        let sourceRect = NSRect(x: cropInset,
                                y: cropInset,
                                width: sourceSize.width - cropInset * 2.0,
                                height: sourceSize.height - cropInset * 2.0)
        image.draw(in: bounds,
                   from: sourceRect,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        context.restoreGState()
    }

    private func drawTemplateImage(_ image: NSImage, in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        color.setFill()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func writePNG(bitmap: NSBitmapImageRep, to url: URL) throws {
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MicLockIcon", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unable to encode PNG at \(url.path)"
            ])
        }

        try pngData.write(to: url, options: .atomic)
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: generate_app_icon.swift <source-svg> <appiconset-dir>\n", stderr)
    exit(64)
}

do {
    try AppIconRenderer(sourceURL: URL(fileURLWithPath: arguments[1]),
                        outputDirectoryURL: URL(fileURLWithPath: arguments[2])).render()
} catch {
    fputs("Failed to generate app icons: \(error.localizedDescription)\n", stderr)
    exit(1)
}
