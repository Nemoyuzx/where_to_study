import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: strip-png-alpha.swift <png> [...]\n", stderr)
    exit(64)
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard
        let image = NSImage(contentsOf: url),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        fputs("Unable to decode PNG: \(path)\n", stderr)
        exit(65)
    }
    let pixelsWide = cgImage.width
    let pixelsHigh = cgImage.height
    guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaNonpremultiplied,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )
    else {
        fputs("Unable to create bitmap: \(path)\n", stderr)
        exit(65)
    }

    guard let context = CGContext(
        data: bitmap.bitmapData,
        width: pixelsWide,
        height: pixelsHigh,
        bitsPerComponent: 8,
        bytesPerRow: bitmap.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Unable to create RGB context: \(path)\n", stderr)
        exit(70)
    }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))

    guard
        let opaqueBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: pixelsWide * 3,
            bitsPerPixel: 24
        ),
        let source = bitmap.bitmapData,
        let destination = opaqueBitmap.bitmapData
    else {
        fputs("Unable to create opaque bitmap: \(path)\n", stderr)
        exit(70)
    }
    for row in 0 ..< pixelsHigh {
        let sourceRow = source.advanced(by: row * bitmap.bytesPerRow)
        let destinationRow = destination.advanced(by: row * opaqueBitmap.bytesPerRow)
        for column in 0 ..< pixelsWide {
            destinationRow[column * 3] = sourceRow[column * 4]
            destinationRow[column * 3 + 1] = sourceRow[column * 4 + 1]
            destinationRow[column * 3 + 2] = sourceRow[column * 4 + 2]
        }
    }

    guard
        let data = opaqueBitmap.representation(using: .png, properties: [:]),
        let encodedBitmap = NSBitmapImageRep(data: data),
        encodedBitmap.pixelsWide == pixelsWide,
        encodedBitmap.pixelsHigh == pixelsHigh,
        !encodedBitmap.hasAlpha
    else {
        fputs("Unable to encode RGB PNG: \(path)\n", stderr)
        exit(70)
    }
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        fputs("Unable to write PNG \(path): \(error)\n", stderr)
        exit(74)
    }
}
