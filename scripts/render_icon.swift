// Original NoteHush artwork. Run from the repository root with:
// swift scripts/render_icon.swift
// Uses offscreen Core Graphics only; never launches an app or reads a workspace.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconError: Error {
  case imageContext
  case imageOutput
}

struct IconDrawing {
  let context: CGContext
  var elements: [String] = []

  func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let value = UInt32(hex, radix: 16) ?? 0
    return CGColor(
      srgbRed: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255, alpha: alpha)
  }

  mutating func rounded(
    _ x: Int, _ y: Int, _ width: Int, _ height: Int, _ radius: Int, fill: String
  ) {
    let path = CGPath(
      roundedRect: CGRect(x: x, y: y, width: width, height: height),
      cornerWidth: CGFloat(radius), cornerHeight: CGFloat(radius), transform: nil)
    context.setFillColor(color(fill))
    context.addPath(path)
    context.fillPath()
    elements.append(
      "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" rx=\"\(radius)\" fill=\"#\(fill)\"/>"
    )
  }

  mutating func draw() {
    // A quiet ink-colored enclosure, three tabs, and a warm paper surface.
    rounded(64, 64, 896, 896, 202, fill: "123B3C")
    rounded(88, 88, 848, 848, 180, fill: "174749")
    rounded(248, 252, 536, 584, 56, fill: "102F32")
    rounded(448, 222, 134, 96, 24, fill: "6EA79E")
    rounded(602, 222, 134, 96, 24, fill: "A3C7BA")
    rounded(240, 242, 544, 568, 48, fill: "F5F8EE")
    rounded(240, 200, 188, 148, 32, fill: "F5F8EE")
    rounded(280, 246, 108, 14, 7, fill: "2C716A")
    rounded(316, 384, 392, 26, 13, fill: "28665F")
    rounded(316, 472, 312, 26, 13, fill: "6B9990")
    rounded(316, 560, 360, 26, 13, fill: "6B9990")
    rounded(316, 648, 224, 26, 13, fill: "6B9990")
    rounded(565, 632, 10, 58, 5, fill: "28665F")
  }
}

func render(pixels: Int, destination: URL) throws -> String {
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw IconError.imageContext }
  context.translateBy(x: 0, y: CGFloat(pixels))
  context.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
  context.setAllowsAntialiasing(true)
  var drawing = IconDrawing(context: context)
  drawing.draw()
  guard let image = context.makeImage(),
    let output = CGImageDestinationCreateWithURL(
      destination as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw IconError.imageOutput }
  CGImageDestinationAddImage(output, image, nil)
  guard CGImageDestinationFinalize(output) else { throw IconError.imageOutput }
  return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <title>NoteHush — tabs and a plain-text page</title>
      \(drawing.elements.joined(separator: "\n  "))
    </svg>

    """
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("App/NoteHush/Resources/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let design = root.appendingPathComponent("Design")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: design, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    let filename = "icon_\(size)x\(size)\(suffix).png"
    let svg = try render(
      pixels: size * scale, destination: iconSet.appendingPathComponent(filename))
    if size * scale == 1024 {
      try svg.write(
        to: design.appendingPathComponent("NoteHushIcon.svg"), atomically: true, encoding: .utf8)
    }
    images.append([
      "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename,
    ])
  }
}
let information: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(
  withJSONObject: ["images": images, "info": information], options: [.prettyPrinted, .sortedKeys]
)
.write(to: iconSet.appendingPathComponent("Contents.json"), options: .atomic)
try JSONSerialization.data(
  withJSONObject: ["info": information], options: [.prettyPrinted, .sortedKeys]
)
.write(to: catalog.appendingPathComponent("Contents.json"), options: .atomic)
print("Generated the original vector artwork and all ten macOS app-icon slots.")
