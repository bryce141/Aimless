import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the Aimless app icon: a closed, wandering loop with a start marker.
// 1024x1024, opaque (App Store rejects icons with an alpha channel), no rounded
// corners (iOS applies its own mask).

let size = 1024
let outPath = CommandLine.arguments[1]

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create context") }

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, 1
    ])!
}

// Dusk gradient — the app is for driving somewhere with no particular place to be.
let top = rgb(30, 44, 74)
let bottom = rgb(11, 16, 30)
let gradient = CGGradient(
    colorsSpace: space,
    colors: [top, bottom] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: [])

// The loop. Polar radius with a few harmonics, which is roughly what the real
// generated loops look like: closed, round-ish, and not remotely a circle.
let center = Double(size) / 2
let base = 296.0

func radius(_ t: Double) -> Double {
    base * (1
        + 0.170 * sin(3 * t + 0.90)
        + 0.085 * sin(5 * t + 2.30)
        - 0.055 * cos(2 * t + 0.40))
}

let steps = 480
var points: [CGPoint] = []
points.reserveCapacity(steps)
for i in 0..<steps {
    let t = Double(i) / Double(steps) * 2 * .pi
    let r = radius(t)
    points.append(CGPoint(x: center + r * cos(t), y: center + r * sin(t)))
}

// The harmonics push the shape off-axis, so it does not sit where its polar
// origin does. Recenter on the actual bounding box or it reads as misaligned.
let xs = points.map(\.x), ys = points.map(\.y)
let dx = center - (xs.min()! + xs.max()!) / 2
let dy = center - (ys.min()! + ys.max()!) / 2
points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }

ctx.setLineWidth(64)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(rgb(245, 241, 232))
ctx.addLines(between: points)
ctx.closePath()
ctx.strokePath()

// Start marker, sitting on the loop like a stop on a transit map. The ring is
// painted in the background color so the marker reads as separate from the line
// even at 40pt.
let start = points[0]

ctx.setFillColor(rgb(16, 25, 45))
ctx.fillEllipse(in: CGRect(
    x: start.x - 78, y: start.y - 78, width: 156, height: 156))

ctx.setFillColor(rgb(48, 209, 88))
ctx.fillEllipse(in: CGRect(
    x: start.x - 52, y: start.y - 52, width: 104, height: 104))

guard let image = ctx.makeImage() else { fatalError("could not render") }
let url = URL(fileURLWithPath: outPath) as CFURL
guard let dest = CGImageDestinationCreateWithURL(
    url, UTType.png.identifier as CFString, 1, nil
) else { fatalError("could not open \(outPath)") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write PNG") }

print("wrote \(outPath)")
