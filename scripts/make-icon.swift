// Draws Tuloy's app icon and saves it as Support/AppIcon.icns.
//
//   make icon
//
// PROVISIONAL, like the menu bar glyph (Tuloy/UI/Glyph.swift): the open ring from branding.txt's
// shortlist, in ube purple and cream. When the logo and colour are chosen, change the drawing
// below, run `make icon`, and commit the new AppIcon.icns.

import AppKit
import SwiftUI

let ube = Color(red: 0x6B / 255, green: 0x3F / 255, blue: 0xA0 / 255)
let ubeLight = Color(red: 0x8A / 255, green: 0x5C / 255, blue: 0xC4 / 255)
let cream = Color(red: 0xFB / 255, green: 0xF7 / 255, blue: 0xEF / 255)

/// The icon at 1024 points, on Apple's grid: an 824-point rounded square in the middle, with room for its shadow.
struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [ubeLight, ube], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 10)
            OpenRing()
                .frame(width: 520, height: 520)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// The glyph's "running" drawing, scaled up: a ring with a gap at the top right and a dot on its way round.
struct OpenRing: View {
    var body: some View {
        Canvas { context, size in
            let line: CGFloat = 64
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - line / 2 - 20
            let gapStart = -72.0, gapEnd = -18.0
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .degrees(gapEnd), endAngle: .degrees(gapStart + 360), clockwise: false)
            context.stroke(ring, with: .color(cream), style: StrokeStyle(lineWidth: line, lineCap: .round))
            let angle = gapStart * .pi / 180
            let tip = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let dot: CGFloat = 148
            context.fill(Path(ellipseIn: CGRect(x: tip.x - dot / 2, y: tip.y - dot / 2, width: dot, height: dot)), with: .color(cream))
        }
    }
}

@MainActor
func png(size: Int) -> Data {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = CGFloat(size) / 1024
    guard let image = renderer.cgImage else { fatalError("Couldn't draw the icon") }
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])!
}

MainActor.assumeIsolated {
    let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Support/AppIcon.icns")
    let folder = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
    try? FileManager.default.removeItem(at: folder)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    for points in [16, 32, 128, 256, 512] {
        try! png(size: points).write(to: folder.appending(path: "icon_\(points)x\(points).png"))
        try! png(size: points * 2).write(to: folder.appending(path: "icon_\(points)x\(points)@2x.png"))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", folder.path, "-o", output.path]
    try! iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
    print("Saved \(output.path)")
}
