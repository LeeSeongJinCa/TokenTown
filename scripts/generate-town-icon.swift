import AppKit
import Foundation

// Original vector icon, rendered using AppKit. No third-party artwork.
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let bg = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 208, yRadius: 208)
NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.87, alpha: 1).setFill()
bg.fill()
func polygon(_ points: [(CGFloat, CGFloat)], _ color: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: points[0].0, y: points[0].1))
    for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
    path.close()
    color.setFill(); path.fill()
}
polygon([(180, 325), (512, 145), (844, 325), (512, 505)], NSColor(calibratedRed: 0.67, green: 0.77, blue: 0.61, alpha: 1))
polygon([(332, 335), (512, 235), (512, 660), (332, 760)], NSColor(calibratedRed: 0.31, green: 0.53, blue: 0.45, alpha: 1))
polygon([(512, 235), (692, 335), (692, 760), (512, 660)], NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.36, alpha: 1))
polygon([(332, 760), (512, 660), (692, 760), (512, 860)], NSColor(calibratedRed: 0.56, green: 0.69, blue: 0.56, alpha: 1))
for floor in 0..<4 {
    let y = CGFloat(345 + floor * 85)
    for x: CGFloat in [370, 435] {
        let slope = (x - 332) * -0.55
        polygon([(x, y + slope + 40), (x + 35, y + slope + 20), (x + 35, y + slope + 65), (x, y + slope + 85)], .white)
    }
    for x: CGFloat in [550, 615] {
        let slope = (x - 512) * 0.55
        polygon([(x, y + slope - 60), (x + 35, y + slope - 40), (x + 35, y + slope + 5), (x, y + slope - 15)], NSColor.white.withAlphaComponent(0.80))
    }
}
image.unlockFocus()
let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
