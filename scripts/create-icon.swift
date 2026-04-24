#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL: URL
if CommandLine.arguments.count > 1 {
    outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    outputURL = URL(fileURLWithPath: ".build/app-icon.iconset")
}

try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let baseSize: CGFloat = 1024

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, in size: CGFloat) -> NSRect {
    let scale = size / baseSize
    return NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat, in size: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, width, height, in: size), xRadius: radius * size / baseSize, yRadius: radius * size / baseSize)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: image.size).fill()

    let background = roundedRect(96, 96, 832, 832, 186, in: size)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.20, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: 1)
    ])?.draw(in: background, angle: -38)

    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    background.lineWidth = max(2, size / 160)
    background.stroke()

    let leftPanel = roundedRect(190, 214, 228, 596, 44, in: size)
    NSColor(calibratedRed: 0.15, green: 0.23, blue: 0.29, alpha: 1).setFill()
    leftPanel.fill()

    let previewPanel = roundedRect(458, 214, 376, 596, 54, in: size)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.54, blue: 0.72, alpha: 1),
        NSColor(calibratedRed: 0.09, green: 0.78, blue: 0.56, alpha: 1)
    ])?.draw(in: previewPanel, angle: 32)

    NSColor(calibratedWhite: 1.0, alpha: 0.82).setStroke()
    previewPanel.lineWidth = max(4, size / 96)
    previewPanel.stroke()

    for index in 0..<4 {
        let y = CGFloat(666 - index * 122)
        let thumb = roundedRect(224, y, 88, 70, 18, in: size)
        NSColor(calibratedRed: 0.50, green: 0.71, blue: 0.84, alpha: 1).setFill()
        thumb.fill()

        let line = roundedRect(330, y + 23, 54, 16, 8, in: size)
        NSColor(calibratedWhite: 1, alpha: 0.42).setFill()
        line.fill()
    }

    let playPath = NSBezierPath()
    playPath.move(to: NSPoint(x: 590 * size / baseSize, y: 440 * size / baseSize))
    playPath.line(to: NSPoint(x: 590 * size / baseSize, y: 590 * size / baseSize))
    playPath.line(to: NSPoint(x: 714 * size / baseSize, y: 515 * size / baseSize))
    playPath.close()
    NSColor.white.setFill()
    playPath.fill()

    let shine = roundedRect(500, 702, 236, 34, 17, in: size)
    NSColor(calibratedWhite: 1, alpha: 0.30).setFill()
    shine.fill()

    let shadow = NSBezierPath(ovalIn: rect(238, 116, 548, 42, in: size))
    NSColor(calibratedWhite: 0, alpha: 0.20).setFill()
    shadow.fill()

    image.unlockFocus()
    return image
}

func writePNG(size: CGFloat, fileName: String) throws {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputURL.appendingPathComponent(fileName))
}

try writePNG(size: 16, fileName: "icon_16x16.png")
try writePNG(size: 32, fileName: "icon_16x16@2x.png")
try writePNG(size: 32, fileName: "icon_32x32.png")
try writePNG(size: 64, fileName: "icon_32x32@2x.png")
try writePNG(size: 128, fileName: "icon_128x128.png")
try writePNG(size: 256, fileName: "icon_128x128@2x.png")
try writePNG(size: 256, fileName: "icon_256x256.png")
try writePNG(size: 512, fileName: "icon_256x256@2x.png")
try writePNG(size: 512, fileName: "icon_512x512.png")
try writePNG(size: 1024, fileName: "icon_512x512@2x.png")
